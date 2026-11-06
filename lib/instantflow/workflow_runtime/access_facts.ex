defmodule Instantflow.WorkflowRuntime.AccessFacts do
  @moduledoc """
  Bounded supporting facts for policy evaluation inside a tenant authorization gate.

  Callers supply current memberships/grants and the pinned ticket/version. Returned
  facts are local to that read and must not be reused as cached authority.
  """
  import Ecto.Query
  alias Instantflow.Repo
  alias Instantflow.Collaboration.{Assignment, Assignments}
  alias Instantflow.Participants.Relationship

  def load([], _ticket, _version), do: %{}

  def load(members, ticket, version) do
    unless Repo.in_transaction?(),
      do: raise(ArgumentError, "Policy facts require a tenant authorization transaction")

    ids = Enum.map(members, & &1.id)
    declared = Enum.map(Map.get(version.definition, "participants", []), & &1["key"])
    assigned_sections = Enum.filter(version.definition["sections"], & &1["assignment"])

    relationships =
      if declared == [],
        do: %{},
        else:
          Repo.all(
            from r in Relationship,
              where:
                r.ticket_id == ^ticket.id and r.workflow_id == ^ticket.workflow_id and
                  r.membership_id in ^ids and r.status == "verified" and not is_nil(r.verified_at) and
                  r.relationship in ^declared,
              select: {r.membership_id, r.relationship}
          )
          |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    assignments =
      if assigned_sections == [],
        do: %{},
        else:
          Repo.all(
            from a in Assignment,
              where: a.ticket_id == ^ticket.id and a.membership_id in ^ids,
              select: {a.membership_id, a.section_key}
          )
          |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    Map.new(members, fn member ->
      eligible =
        Enum.filter(assigned_sections, fn section ->
          section["key"] in Map.get(assignments, member.id, []) and
            Assignments.eligible?(member, version, section["assignment"])
        end)

      {member.id,
       %{
         relationships: Map.get(relationships, member.id, []),
         assignments: Enum.map(eligible, & &1["key"])
       }}
    end)
  end
end
