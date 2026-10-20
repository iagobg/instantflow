defmodule Instantflow.WorkflowRuntime.Policy do
  @moduledoc "Sprint 01 authorization hooks: symbolic roles bind to local profiles and explicit record scopes."
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
    transition["from"] == ticket.stage and
      (not Map.get(transition, "disallow_requester", false) or
         actor.user_id != ticket.requester_id) and
      Enum.any?(transition["actors"], &actor?(actor, ticket, version, &1))
  end

  defp actor?(actor, ticket, version, spec) do
    actor.role in Map.get(version.bindings["roles"], spec["role"], []) and
      case spec["scope"] do
        "requester" -> actor.user_id == ticket.requester_id
        "assigned_department" -> actor.department_id == ticket.assigned_department_id
        _ -> false
      end
  end
end
