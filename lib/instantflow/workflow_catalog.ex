defmodule Instantflow.WorkflowCatalog do
  @moduledoc "Publishes validated immutable definitions with local bindings. Publication grants no ticket access."
  import Ecto.Query
  alias Instantflow.{Identity, Repo, Tenant}
  alias Instantflow.WorkflowCatalog.{Definition, Version, Workflow}

  def publish(actor, definition, bindings, expected_version \\ 0) do
    Tenant.transaction(actor, fn actor ->
      actor = Identity.lock_scope!(actor)
      unless actor.role == "admin", do: Repo.rollback(:forbidden)

      case Definition.validate(definition) do
        :ok -> :ok
        {:error, errors} -> Repo.rollback({:invalid_definition, errors})
      end

      Instantflow.Calculations.Catalogue.validate_bindings!(actor, definition)

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

      if latest > 0 do
        previous = Repo.get_by!(Version, workflow_id: workflow.id, number: latest)

        if Instantflow.WorkflowCatalog.Workspaces.operational?(previous.definition) and
             !Instantflow.WorkflowCatalog.Workspaces.operational?(definition),
           do: Repo.rollback(:incompatible_workspace)
      end

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
            left_join: retired in "retired_workflow_versions",
            on: retired.version_id == v.id,
            where: v.organization_id == ^actor.organization_id,
            distinct: v.workflow_id,
            order_by: [asc: v.workflow_id, desc: v.number],
            select: {v, retired.version_id},
            preload: [:workflow]
        )
        |> Enum.filter(fn {version, retired} ->
          is_nil(retired) and Instantflow.WorkflowRuntime.Policy.create?(scope, version)
        end)
        |> Enum.map(&elem(&1, 0))
    end
  end

  def valid_bindings?(d, bindings, organization_id, mode \\ :complete),
    do: Instantflow.WorkflowCatalog.Bindings.valid?(d, bindings, organization_id, mode)
end
