defmodule Instantflow.Tenant do
  @moduledoc "Lock order: organization, authorization gate, user, membership, business rows. Reads share actor locks; mutations select write locks before entering the callback."
  import Ecto.Query
  alias Instantflow.Repo
  alias Instantflow.Identity.{Membership, Organization, User}
  alias Instantflow.Tenant.ReadContext
  @read_depth {__MODULE__, :read_depth}
  @read_lock_mode {__MODULE__, :read_lock_mode}

  @doc "Lease one pooled connection for a composite web read; each context still owns its authorization transaction."
  def with_connection(fun) when is_function(fun, 0), do: Repo.checkout(fun)

  def transaction(%Membership{organization_id: id} = scope, fun) when is_integer(id) do
    require_writable!()
    scoped_transaction(scope, fun, :write)
  end

  def transaction(_, _), do: {:error, :forbidden}

  def authorize_change(%Membership{} = scope, fun) do
    require_writable!()
    scoped_transaction(scope, fun, :exclusive)
  end

  def authorize_change(_, _), do: {:error, :forbidden}

  defp scoped_transaction(%Membership{organization_id: id} = scope, fun, mode)
       when is_integer(id) do
    raw_scoped(id, fn organization ->
      # Shared command/read gates and exclusive permission changes use the same order.
      function =
        if mode == :exclusive, do: "pg_advisory_xact_lock", else: "pg_advisory_xact_lock_shared"

      Repo.query!("SELECT #{function}(hashtextextended('access:' || $1::text, 0))", [
        to_string(id)
      ])

      user =
        from(u in User, where: u.id == ^scope.user_id)
        |> actor_lock(mode)
        |> Repo.one()

      member =
        from(m in Membership,
          where: m.organization_id == ^id and m.user_id == ^scope.user_id and m.id == ^scope.id
        )
        |> actor_lock(mode)
        |> Repo.one()

      unless user && user.active && member && member.active, do: Repo.rollback(:forbidden)
      fresh = Instantflow.Access.load(member)
      fun.(%{fresh | user: user, organization: organization})
    end)
  end

  defp scoped_transaction(_, _, _), do: {:error, :forbidden}

  defp actor_lock(query, :read), do: lock(query, "FOR SHARE")
  defp actor_lock(query, mode) when mode in [:write, :exclusive], do: lock(query, "FOR UPDATE")

  # Infrastructure only: invitations prove a token; jobs carry persisted ownership. Neither accepts browser tenant claims.
  def raw(id, fun) when is_integer(id) and id > 0 do
    require_writable!()
    raw_scoped(id, fn _organization -> fun.() end)
  end

  def raw(_, _), do: {:error, :forbidden}

  defp raw_scoped(id, fun) when is_integer(id) and id > 0 do
    Repo.transaction(fn ->
      [[previous, previous_role]] =
        Repo.query!("SELECT current_setting('instantflow.organization_id', true), current_user").rows

      if previous not in [nil, "", to_string(id)], do: Repo.rollback(:scope_mismatch)
      Repo.query!("SET LOCAL ROLE instantflow_runtime")
      Repo.query!("SELECT set_config('instantflow.organization_id', $1, true)", [to_string(id)])

      generation =
        from g in "workflow_catalog_generations",
          where: g.organization_id == parent_as(:organization).id,
          select: g.generation

      organization =
        Repo.one(
          from o in Organization,
            as: :organization,
            where: o.id == ^id,
            select_merge: %{catalog_generation: coalesce(subquery(generation), 0)},
            lock: "FOR SHARE"
        )

      unless organization && organization.status == "active", do: Repo.rollback(:unavailable)
      result = fun.(organization)
      # Restore both settings even when nested in a caller's existing transaction
      # (including a sandbox transaction); committing a savepoint does not reset them.
      Repo.query!(
        "SELECT set_config('instantflow.organization_id', $1, true), set_config('role', $2, true)",
        [previous || "", previous_role]
      )

      result
    end)
  end

  defp raw_scoped(_, _), do: {:error, :forbidden}

  @doc "Infrastructure jobs acquire the shared authorization gate before business locks."
  def authorization_gate!(id) do
    Repo.query!(
      "SELECT pg_advisory_xact_lock_shared(hashtextextended('access:' || $1::text, 0))",
      [to_string(id)]
    )
  end

  def read(scope, fun, fallback \\ nil) do
    # Reads nested in a write/untyped transaction retain write locks. Choosing
    # share locks there could require an unsafe upgrade later in that transaction.
    previous_mode = Process.get(@read_lock_mode)
    mode = previous_mode || if(Repo.in_transaction?(), do: :write, else: :read)

    read = fn fresh ->
      depth = Process.get(@read_depth, 0)
      Process.put(@read_depth, depth + 1)
      Process.put(@read_lock_mode, mode)

      try do
        fun.(fresh)
      after
        if depth == 0, do: Process.delete(@read_depth), else: Process.put(@read_depth, depth)

        if is_nil(previous_mode),
          do: Process.delete(@read_lock_mode),
          else: Process.put(@read_lock_mode, previous_mode)
      end
    end

    case scoped_transaction(scope, read, mode) do
      {:ok, value} ->
        value

      {:error, reason} ->
        # A nested rollback aborts the enclosing transaction too. Propagate it
        # before the outer boundary attempts any further reads or restoration.
        if Repo.in_transaction?(), do: Repo.rollback(reason), else: fallback
    end
  end

  @doc false
  def lock_for_read(query) do
    case Process.get(@read_lock_mode) do
      :read -> lock(query, "FOR SHARE")
      :write -> lock(query, "FOR UPDATE")
      _ -> raise ArgumentError, "Read locks require a tenant read boundary"
    end
  end

  @doc "Compose reads under one current authorization boundary. Contexts expire when the callback returns."
  def read_context(scope, fun, fallback \\ nil) do
    read(
      scope,
      fn fresh ->
        context = %ReadContext{ref: make_ref()}
        key = {__MODULE__, context.ref}
        Process.put(key, %{scope: fresh, repo: Repo.get_dynamic_repo(), cache: %{}})

        try do
          fun.(context)
        after
          Process.delete(key)
        end
      end,
      fallback
    )
  end

  @doc "Current scope for a live context. This does not accept a cached membership as authority."
  def context_scope!(context), do: context_state!(context).scope

  @doc "Reuse a read result only within the owning process, repository and read callback."
  def context_fetch!(context, key, fun) do
    state = context_state!(context)

    case Map.fetch(state.cache, key) do
      {:ok, value} ->
        value

      :error ->
        value = fun.(state.scope)
        current = context_state!(context)

        Process.put({__MODULE__, context.ref}, %{
          current
          | cache: Map.put(current.cache, key, value)
        })

        value
    end
  end

  defp context_state!(%ReadContext{ref: ref}) when is_reference(ref) do
    case Process.get({__MODULE__, ref}) do
      %{repo: repo} = state ->
        if repo == Repo.get_dynamic_repo() and Repo.in_transaction?(),
          do: state,
          else:
            raise(ArgumentError, "Read context belongs to a different repository or transaction")

      _ ->
        raise ArgumentError, "Read context is expired or belongs to another process"
    end
  end

  defp context_state!(_), do: raise(ArgumentError, "Expected a live tenant read context")

  defp require_writable! do
    if Process.get(@read_depth, 0) > 0,
      do: raise(ArgumentError, "Mutation entry points cannot run inside a tenant read boundary")
  end

  def scope(user_id, organization_id) do
    case raw_scoped(organization_id, fn _organization ->
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
