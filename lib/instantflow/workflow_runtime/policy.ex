defmodule Instantflow.WorkflowRuntime.Policy do
  @moduledoc "Deny-by-default role, department, relationship, stage, and section policies."
  alias Instantflow.Access
  alias Instantflow.WorkflowRuntime.LegacyAccess

  def discover?(actor, ticket, version) do
    not LegacyAccess.parent_portal?(actor, version) and
      Enum.any?(version.definition["sections"], &section?(actor, ticket, version, &1, :read))
  end

  def create?(actor, version) do
    not LegacyAccess.parent_portal?(actor, version) and
      Enum.any?(
        version.definition["creation"]["roles"],
        &Access.role?(actor, Map.get(version.bindings["roles"], &1, []))
      )
  end

  def section?(actor, ticket, version, section, mode, facts \\ :live)

  def section?(actor, ticket, version, section, :read, facts),
    do: Enum.any?(section["access"], &(&1["read"] and actor?(actor, ticket, version, &1, facts)))

  def section?(actor, ticket, version, section, :edit, facts),
    do:
      not Instantflow.Calculations.Contract.computed?(version.definition, section["key"]) and
        Enum.any?(
          section["access"],
          &(ticket.stage in &1["edit_stages"] and actor?(actor, ticket, version, &1, facts))
        )

  def transition?(actor, ticket, version, transition, facts \\ :live) do
    transition["from"] == ticket.stage and
      transition_actor?(actor, ticket, version, transition, facts)
  end

  defp transition_actor?(actor, ticket, version, transition, facts \\ :live) do
    (not Map.get(transition, "disallow_requester", false) or
       actor.user_id != ticket.requester_id) and
      (not Map.get(transition, "finance_sensitive", false) or actor.user_id != ticket.requester_id) and
      Enum.any?(transition["actors"], &actor?(actor, ticket, version, &1, facts))
  end

  def actor?(actor, ticket, version, spec, facts \\ :live) do
    (not LegacyAccess.parent_portal?(actor, version) or
       LegacyAccess.guardian?(actor, ticket, version)) and
      Enum.any?(Access.profiles(actor), fn profile ->
        profile.role in Map.get(version.bindings["roles"], spec["role"], []) and
          case spec["scope"] do
            "participant" ->
              if facts == :live,
                do:
                  Instantflow.Participants.linked?(actor, ticket, version, spec["relationship"]),
                else: spec["relationship"] in facts.relationships

            "assigned_user" ->
              if facts == :live,
                do:
                  Instantflow.Collaboration.Assignments.assigned?(
                    actor,
                    ticket,
                    version,
                    spec["assignment_key"]
                  ),
                else: spec["assignment_key"] in facts.assignments

            "requester" ->
              actor.user_id == ticket.requester_id

            "guardian" ->
              facts == :live and LegacyAccess.guardian?(actor, ticket, version)

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
        &(&1["scope"] in ~w(assigned_department workflow_department) and
            actor?(actor, ticket, version, &1))
      )
    end)
  end

  def history?(actor, ticket, version, %{operation: "save:" <> key}) do
    case Enum.find(version.definition["sections"], &(&1["key"] == key)) do
      nil -> false
      section -> section?(actor, ticket, version, section, :read)
    end
  end

  def history?(actor, ticket, version, %{operation: "assign:" <> key}) do
    section = Enum.find(version.definition["sections"], &(&1["key"] == key))
    section && Instantflow.Collaboration.Assignments.manager?(actor, ticket, version, section)
  end

  def history?(actor, ticket, version, %{operation: "participant:" <> operation}) do
    case String.split(operation, ":", parts: 2) do
      [_, key] -> Instantflow.Participants.manage?(actor, ticket, version, key)
      _ -> false
    end
  end

  def history?(_actor, _ticket, _version, %{operation: "create"}), do: true

  def history?(actor, ticket, version, %{operation: "release:" <> key}),
    do:
      Instantflow.Delivery.Curated.authorized?(
        actor,
        ticket,
        version,
        Instantflow.WorkflowCatalog.Communications.find(version.definition, key)
      )

  def history?(actor, ticket, version, %{operation: "document:" <> operation}) do
    case String.split(operation, ":", parts: 2) do
      [_, ref] ->
        key = ref |> String.split(".", parts: 2) |> hd()
        section = Enum.find(version.definition["sections"], &(&1["key"] == key))
        section != nil and section?(actor, ticket, version, section, :read)

      _ ->
        false
    end
  end

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
