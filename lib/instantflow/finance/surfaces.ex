defmodule Instantflow.Finance.Surfaces do
  @moduledoc "Bounded process or explicitly authorized shared-account summaries and existing finance commands."
  import Ecto.Query
  alias Instantflow.{Access, Finance, Repo, Tenant}
  alias Instantflow.Finance.{Account, Hold}
  alias Instantflow.WorkflowCatalog.Version
  alias Instantflow.WorkflowRuntime.Projections

  def load(actor, workflow_id) do
    Tenant.read(
      actor,
      fn scope ->
        version =
          Repo.one(
            from v in Version,
              where: v.workflow_id == ^workflow_id,
              order_by: [desc: v.number],
              limit: 1
          )

        spec = version && get_in(version.definition, ["interface", "finance"])

        if spec do
          allowed? =
            Enum.any?(
              spec["view_roles"],
              &Access.role?(scope, version.bindings["roles"][&1] || [])
            )

          bound = version.bindings["budgets"][spec["account_binding"]]
          current = bound && Repo.get(Account, bound)
          summaries = if allowed?, do: summaries(scope, version, spec, current), else: []

          %{
            summaries: summaries,
            scope: spec["scope"],
            can_create?: scope.role == "admin",
            can_allocate?:
              current &&
                Enum.any?(
                  Access.profiles(scope),
                  &(&1.role == "finance_allocator" and &1.department_id == current.department_id)
                ),
            account_options:
              if(current && Finance.view?(scope, current),
                do: [{current.name, current.id}],
                else: []
              ),
            departments:
              if(scope.role == "admin",
                do:
                  Repo.all(
                    from d in Instantflow.Identity.Department,
                      order_by: d.id,
                      limit: 100,
                      select: {d.name, d.id}
                  ),
                else: []
              )
          }
        else
          empty()
        end
      end,
      empty()
    )
  end

  defp summaries(scope, _, %{"scope" => "shared_account"}, account) do
    if account && Finance.view?(scope, account),
      do: [
        %{
          id: account.id,
          name: account.name,
          reserved: account.reserved,
          spent: account.spent,
          allocated: account.allocated,
          available: account.allocated - account.reserved - account.spent
        }
      ],
      else: []
  end

  defp summaries(scope, version, _, _account) do
    ids = Projections.authorized_query(scope, version.workflow_id) |> select([t], t.id)

    Repo.all(
      from h in Hold,
        join: a in Account,
        on: a.id == h.account_id,
        where: h.ticket_id in subquery(ids),
        group_by: [a.id, a.name],
        order_by: a.id,
        limit: 100,
        select: %{
          id: a.id,
          name: a.name,
          reserved:
            fragment(
              "SUM(CASE WHEN ? = 'reserved' THEN ? ELSE 0 END)::bigint",
              h.status,
              h.amount
            ),
          spent:
            fragment("SUM(CASE WHEN ? = 'posted' THEN ? ELSE 0 END)::bigint", h.status, h.amount)
        }
    )
    |> Enum.map(&Map.merge(&1, %{allocated: nil, available: nil}))
  end

  def empty,
    do: %{
      summaries: [],
      scope: "process",
      can_create?: false,
      can_allocate?: false,
      account_options: [],
      departments: []
    }
end
