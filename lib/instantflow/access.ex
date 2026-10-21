defmodule Instantflow.Access do
  @moduledoc "Local grants bind a role to a department; administration grants no implicit record access."
  import Ecto.Query
  alias Instantflow.{Repo, Tenant}
  alias Instantflow.Access.Grant
  alias Instantflow.Identity.{Department, Membership}

  @roles ~w(teacher admissions head finance operations it dean counselor)
  def roles, do: @roles
  def binding_roles, do: ["admin", "staff", "parent" | @roles]

  def load(%Membership{} = actor) do
    grants =
      Repo.all(
        from g in Grant,
          where: g.membership_id == ^actor.id and g.organization_id == ^actor.organization_id
      )

    %{actor | grants: grants}
  end

  def profiles(actor),
    do: [%{role: actor.role, department_id: actor.department_id} | actor.grants]

  def role?(actor, roles), do: Enum.any?(profiles(actor), &(&1.role in roles))
  def department?(actor, id), do: Enum.any?(profiles(actor), &(&1.department_id == id))

  def grant(actor, member_id, department_id, role) do
    change(actor, fn a ->
      member =
        Repo.get_by(Membership, id: member_id, organization_id: a.organization_id, active: true)

      department = Repo.get_by(Department, id: department_id, organization_id: a.organization_id)
      unless member && department && role in @roles, do: Repo.rollback(:forbidden)

      grant =
        Repo.get_by(Grant,
          organization_id: a.organization_id,
          membership_id: member.id,
          department_id: department.id,
          role: role
        ) ||
          Repo.insert!(%Grant{
            organization_id: a.organization_id,
            membership_id: member.id,
            department_id: department.id,
            role: role
          })

      audit(a, "grant_added", grant)
      {member, grant}
    end)
  end

  def revoke(actor, id) do
    change(actor, fn a ->
      grant = Repo.get_by(Grant, id: id, organization_id: a.organization_id)
      unless grant, do: Repo.rollback(:forbidden)
      member = Repo.get!(Membership, grant.membership_id)
      Repo.delete!(grant)
      audit(a, "grant_revoked", grant)
      {member, grant}
    end)
  end

  defp change(actor, fun) do
    result =
      Tenant.authorize_change(actor, fn a ->
        unless a.role == "admin", do: Repo.rollback(:forbidden)
        fun.(a)
      end)

    case result do
      {:ok, {member, _}} ->
        Phoenix.PubSub.broadcast(
          Instantflow.PubSub,
          "organization:#{member.organization_id}:user:#{member.user_id}",
          :permissions_changed
        )

      _ ->
        :ok
    end

    result
  end

  defp audit(a, operation, grant) do
    Repo.insert!(%Instantflow.Organizations.Event{
      organization_id: a.organization_id,
      actor_id: a.user_id,
      operation: operation,
      key:
        "#{operation}:member:#{grant.membership_id}:department:#{grant.department_id}:role:#{grant.role}:#{Ecto.UUID.generate()}"
    })
  end
end
