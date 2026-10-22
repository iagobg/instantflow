defmodule Instantflow.WorkflowCatalog.Workspaces do
  @moduledoc "Tenant-authorized discovery and access for published process workspaces."
  import Ecto.Query
  alias Instantflow.{Repo, Tenant}
  alias Instantflow.WorkflowCatalog.Version

  # Stable facade for callers; definition-only behavior lives in Interface.
  defdelegate block_label(block), to: Instantflow.WorkflowCatalog.Interface
  defdelegate blocks(), to: Instantflow.WorkflowCatalog.Interface
  defdelegate operational_blocks(), to: Instantflow.WorkflowCatalog.Interface
  defdelegate operational?(definition), to: Instantflow.WorkflowCatalog.Interface
  defdelegate labels(definition), to: Instantflow.WorkflowCatalog.Interface
  defdelegate pages(definition), to: Instantflow.WorkflowCatalog.Interface
  defdelegate close_transition(definition), to: Instantflow.WorkflowCatalog.Interface
  defdelegate configuration(definition), to: Instantflow.WorkflowCatalog.Interface
  defdelegate validate(definition), to: Instantflow.WorkflowCatalog.Interface

  def allowed?(scope, version, action) do
    roles =
      get_in(version.definition, ["interface", "access", action]) ||
        version.definition["creation"]["roles"]

    Enum.any?(roles, &Instantflow.Access.role?(scope, version.bindings["roles"][&1] || []))
  end

  def latest do
    Repo.all(
      from v in Version,
        distinct: v.workflow_id,
        order_by: [asc: v.workflow_id, desc: v.number],
        preload: [:workflow]
    )
  end

  def installed(scope) do
    Tenant.read(
      scope,
      fn fresh ->
        participant_workflows =
          Repo.all(
            from v in Version,
              where:
                fragment("jsonb_path_exists(?, '$.interface.pages[*].participant')", v.definition),
              distinct: v.workflow_id,
              select: v.workflow_id
          )

        Enum.filter(latest(), fn version ->
          if version.workflow_id in participant_workflows do
            # Participation gets its own authorized discovery. Candidate eligibility
            # alone must not reveal the staff workspace, even after republication.
            Instantflow.WorkflowRuntime.ParticipantPolicy.staff_workspace?(fresh, version)
          else
            accessible?(fresh, version)
          end
        end)
      end,
      []
    )
  end

  def get(scope, id) do
    Enum.find(installed(scope), &(&1.workflow_id == id))
  end

  defp accessible?(scope, version) do
    Enum.any?(
      version.definition["role_requirements"],
      &Instantflow.Access.role?(scope, version.bindings["roles"][&1["key"]] || [])
    )
  end

  def navigation(scope) do
    installed(scope) |> Enum.map(&%{id: &1.workflow_id, label: &1.definition["name"]})
  end
end
