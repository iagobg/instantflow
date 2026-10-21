defmodule Instantflow.WorkflowCatalog do
  @moduledoc "Publishes validated immutable definitions with local bindings. Publication grants no ticket access."
  import Ecto.Query
  alias Instantflow.{Identity, Repo, Tenant}
  alias Instantflow.Identity.{Department}
  alias Instantflow.WorkflowCatalog.{Definition, Version, Workflow}

  def publish(actor, definition, bindings, expected_version \\ 0) do
    Tenant.transaction(actor, fn actor ->
      actor = Identity.lock_scope!(actor)
      unless actor.role == "admin", do: Repo.rollback(:forbidden)

      case Definition.validate(definition) do
        :ok -> :ok
        {:error, errors} -> Repo.rollback({:invalid_definition, errors})
      end

      unless valid_bindings?(definition, bindings, actor.organization_id),
        do: Repo.rollback(:invalid_bindings)

      Repo.query!("SELECT pg_advisory_xact_lock($1)", [actor.organization_id])

      workflow =
        Repo.one(
          from w in Workflow,
            where:
              w.organization_id == ^actor.organization_id and w.key == ^definition["template_key"],
            lock: "FOR UPDATE"
        ) ||
          Repo.insert!(%Workflow{
            organization_id: actor.organization_id,
            key: definition["template_key"],
            name: definition["name"]
          })

      latest =
        Repo.one(from v in Version, where: v.workflow_id == ^workflow.id, select: max(v.number)) ||
          0

      unless latest == expected_version, do: Repo.rollback(:conflict)

      Repo.insert!(%Version{
        workflow_id: workflow.id,
        number: latest + 1,
        definition: definition,
        bindings: bindings,
        published_by_id: actor.user_id,
        organization_id: actor.organization_id
      })
    end)
  end

  def available(actor), do: Tenant.read(actor, &available_scoped/1, [])

  defp available_scoped(actor) do
    case Identity.scope(actor.user_id, actor.organization_id) do
      nil ->
        []

      scope ->
        Repo.all(
          from v in Version,
            where: v.organization_id == ^actor.organization_id,
            distinct: v.workflow_id,
            order_by: [asc: v.workflow_id, desc: v.number],
            preload: [:workflow]
        )
        |> Enum.filter(fn v ->
          Enum.any?(
            v.definition["creation"]["roles"],
            &Instantflow.Access.role?(scope, v.bindings["roles"][&1])
          )
        end)
    end
  end

  def valid_bindings?(d, bindings, organization_id, mode \\ :complete)

  def valid_bindings?(
        d,
        %{"roles" => roles, "departments" => departments} = bindings,
        organization_id,
        mode
      )
      when is_map(roles) and is_map(departments) do
    Enum.all?(Map.keys(bindings), &(&1 in ~w(departments roles budgets))) and
      binding_keys?(roles, d["role_requirements"], mode) and
      Enum.all?(roles, fn {_, list} ->
        is_list(list) and list != [] and
          Enum.all?(list, &(&1 in Instantflow.Access.binding_roles()))
      end) and
      binding_keys?(departments, Enum.filter(d["bindings"], &(&1["type"] == "department")), mode) and
      budget_bindings?(d, bindings, organization_id, mode) and
      Enum.all?(departments, fn {_, id} ->
        is_integer(id) and
          Repo.exists?(
            from dep in Department,
              where: dep.id == ^id and dep.organization_id == ^organization_id
          )
      end)
  end

  def valid_bindings?(_, _, _, _), do: false

  defp budget_bindings?(d, bindings, organization_id, mode) do
    budgets = Map.get(bindings, "budgets", %{})

    is_map(budgets) and
      binding_keys?(budgets, Enum.filter(d["bindings"], &(&1["type"] == "budget")), mode) and
      Enum.all?(budgets, fn {_, id} ->
        is_integer(id) and
          Repo.exists?(
            from b in Instantflow.Finance.Account,
              where: b.id == ^id and b.organization_id == ^organization_id
          )
      end)
  end

  defp binding_keys?(bindings, requirements, mode) do
    keys = Enum.map(requirements, & &1["key"])

    Enum.all?(Map.keys(bindings), &(&1 in keys)) and
      (mode == :partial or Enum.sort(Map.keys(bindings)) == Enum.sort(keys))
  end
end
