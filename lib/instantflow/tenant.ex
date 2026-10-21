defmodule Instantflow.Tenant do
  @moduledoc "Lock order: organization, authorization gate, user, membership, business rows."
  import Ecto.Query
  alias Instantflow.Repo
  alias Instantflow.Identity.{Membership, Organization, User}

  def transaction(%Membership{organization_id: id} = scope, fun) when is_integer(id) do
    scoped_transaction(scope, fun, :shared)
  end

  def transaction(_, _), do: {:error, :forbidden}

  def authorize_change(%Membership{} = scope, fun), do: scoped_transaction(scope, fun, :exclusive)
  def authorize_change(_, _), do: {:error, :forbidden}

  defp scoped_transaction(%Membership{organization_id: id} = scope, fun, mode) do
    raw(id, fn ->
      # Shared command/read gates and exclusive permission changes use the same order.
      function =
        if mode == :exclusive, do: "pg_advisory_xact_lock", else: "pg_advisory_xact_lock_shared"

      Repo.query!("SELECT #{function}(hashtextextended('access:' || $1::text, 0))", [
        to_string(id)
      ])

      user = Repo.one(from u in User, where: u.id == ^scope.user_id, lock: "FOR UPDATE")

      member =
        Repo.one(
          from m in Membership,
            where: m.organization_id == ^id and m.user_id == ^scope.user_id and m.id == ^scope.id,
            lock: "FOR UPDATE"
        )

      unless user && user.active && member && member.active, do: Repo.rollback(:forbidden)
      fun.(Instantflow.Access.load(member))
    end)
  end

  # Infrastructure only: invitations prove a token; jobs carry persisted ownership. Neither accepts browser tenant claims.
  def raw(id, fun) when is_integer(id) and id > 0 do
    Repo.transaction(fn ->
      previous =
        Repo.query!("SELECT current_setting('instantflow.organization_id', true)").rows
        |> hd()
        |> hd()

      previous_role = Repo.query!("SELECT current_user").rows |> hd() |> hd()
      if previous not in [nil, "", to_string(id)], do: Repo.rollback(:scope_mismatch)
      Repo.query!("SET LOCAL ROLE instantflow_runtime")
      Repo.query!("SELECT set_config('instantflow.organization_id', $1, true)", [to_string(id)])
      organization = Repo.one(from o in Organization, where: o.id == ^id, lock: "FOR SHARE")
      unless organization && organization.status == "active", do: Repo.rollback(:unavailable)
      result = fun.()
      Repo.query!("SELECT set_config('instantflow.organization_id', $1, true)", [previous || ""])
      Repo.query!("SELECT set_config('role', $1, true)", [previous_role])
      result
    end)
  end

  def raw(_, _), do: {:error, :forbidden}

  def read(scope, fun, fallback \\ nil) do
    case transaction(scope, fun) do
      {:ok, value} -> value
      _ -> fallback
    end
  end

  def scope(user_id, organization_id) do
    case raw(organization_id, fn ->
           member =
             Repo.one(
               from m in Membership,
                 join: u in assoc(m, :user),
                 where:
                   m.organization_id == ^organization_id and m.user_id == ^user_id and m.active and
                     u.active,
                 preload: [:user, :department, :organization]
             )

           if member, do: Instantflow.Access.load(member)
         end) do
      {:ok, scope} ->
        scope

      _ ->
        nil
    end
  end
end
