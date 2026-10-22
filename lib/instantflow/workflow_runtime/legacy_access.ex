defmodule Instantflow.WorkflowRuntime.LegacyAccess do
  @moduledoc """
  Explicit compatibility boundary for historical school authorization.

  Definitions declaring participants use only their configured relationships.
  The legacy portal and guardian scope remain available for pre-migration
  definitions until the populated replacement gate in Sprint 11.
  """
  import Ecto.Query
  alias Instantflow.Repo
  alias Instantflow.Participants.Relationship
  alias Instantflow.WorkflowRuntime.Ticket

  def parent_portal?(actor, version),
    do: actor.role == "parent" and legacy_definition?(version.definition)

  def legacy_definition?(definition) do
    not Map.has_key?(definition, "participants") and
      is_nil(get_in(definition, ["interface", "finance"])) and
      not Map.has_key?(definition, "communications") and
      not Enum.any?(definition["transitions"], &Map.has_key?(&1, "reset"))
  end

  def guardian?(actor, ticket, version) do
    legacy_definition?(version.definition) and
      guardian_relationship?(actor, ticket.id)
  end

  @doc "Compatibility mapping lookup; caller must hold the tenant authorization gate."
  def guardian_relationship?(actor, ticket_id) do
    Repo.exists?(
      from r in Relationship,
        join: t in Ticket,
        on: t.id == r.ticket_id and t.workflow_id == r.workflow_id,
        where:
          r.organization_id == ^actor.organization_id and
            t.organization_id == ^actor.organization_id and r.ticket_id == ^ticket_id and
            r.membership_id == ^actor.id and not is_nil(r.legacy_guardian_link_id) and
            r.relationship == "legacy_guardian" and r.status == "verified" and
            not is_nil(r.verified_at)
    )
  end
end
