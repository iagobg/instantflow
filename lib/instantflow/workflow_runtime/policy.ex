defmodule Instantflow.WorkflowRuntime.Policy do
  @moduledoc "Deny-by-default role, department, relationship, stage, and section policies."
  alias Instantflow.Access

  def discover?(%{role: "parent"}, _ticket, _version), do: false

  def discover?(actor, ticket, version) do
    Enum.any?(version.definition["sections"], &section?(actor, ticket, version, &1, :read))
  end

  def section?(actor, ticket, version, section, :read),
    do: Enum.any?(section["access"], &(&1["read"] and actor?(actor, ticket, version, &1)))

  def section?(actor, ticket, version, section, :edit),
    do:
      Enum.any?(
        section["access"],
        &(ticket.stage in &1["edit_stages"] and actor?(actor, ticket, version, &1))
      )

  def transition?(actor, ticket, version, transition) do
    transition["from"] == ticket.stage and transition_actor?(actor, ticket, version, transition)
  end

  defp transition_actor?(actor, ticket, version, transition) do
    (not Map.get(transition, "disallow_requester", false) or
       actor.user_id != ticket.requester_id) and
      (not Map.get(transition, "finance_sensitive", false) or actor.user_id != ticket.requester_id) and
      Enum.any?(transition["actors"], &actor?(actor, ticket, version, &1))
  end

  def actor?(actor, ticket, version, spec) do
    (actor.role != "parent" or Instantflow.Enrollment.guardian?(actor, ticket.id)) and
      Enum.any?(Access.profiles(actor), fn profile ->
        profile.role in Map.get(version.bindings["roles"], spec["role"], []) and
          case spec["scope"] do
            "requester" ->
              actor.user_id == ticket.requester_id

            "guardian" ->
              Instantflow.Enrollment.guardian?(actor, ticket.id)

            "workflow_department" ->
              profile.department_id == version.bindings["departments"][spec["department_binding"]]

            "assigned_department" ->
              profile.department_id == ticket.assigned_department_id

            _ ->
              false
          end
      end)
  end

  def retry?(actor, ticket, version) do
    Enum.any?(version.definition["transitions"], fn edge ->
      Enum.any?(
        edge["actors"],
        &(&1["scope"] == "assigned_department" and actor?(actor, ticket, version, &1))
      )
    end)
  end

  def history?(actor, ticket, version, %{operation: "save:" <> key}) do
    case Enum.find(version.definition["sections"], &(&1["key"] == key)) do
      nil -> false
      section -> section?(actor, ticket, version, section, :read)
    end
  end

  def history?(_actor, _ticket, _version, %{operation: "create"}), do: true

  def history?(actor, ticket, version, event) do
    case Enum.find(version.definition["transitions"], &(&1["key"] == event.operation)) do
      nil ->
        false

      edge ->
        Map.get(edge, "history_visibility", "participants") == "participants" or
          transition_actor?(actor, ticket, version, edge)
    end
  end
end
