defmodule Instantflow.WorkflowRuntime.ParticipantPolicy do
  @moduledoc "Current participant page admission, independent of projection field and command authority."
  def staff_workspace?(scope, version) do
    Instantflow.WorkflowRuntime.Policy.create?(scope, version) or
      Enum.any?(
        get_in(version.definition, ["interface", "access", "view"]) || [],
        &Instantflow.Access.role?(scope, version.bindings["roles"][&1] || [])
      )
  end

  def visible?(scope, version, page) do
    Enum.any?(page["participant"]["visibility_roles"], fn role ->
      Instantflow.Access.role?(scope, Map.get(version.bindings["roles"], role, []))
    end)
  end

  def allowed?(scope, ticket, version, page) do
    visible?(scope, version, page) and
      Instantflow.WorkflowRuntime.Policy.discover?(scope, ticket, version) and
      Enum.any?(
        page["participant"]["audience"],
        &Instantflow.WorkflowRuntime.Policy.actor?(scope, ticket, version, &1)
      )
  end
end
