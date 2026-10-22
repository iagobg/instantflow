defmodule Instantflow.PrivateDocuments.LegacyPolicy do
  @moduledoc "Explicit compatibility rules for attachment fields without a declared policy."
  alias Instantflow.Enrollment
  alias Instantflow.WorkflowRuntime.Policy

  def allowed?(actor, ticket, version, section, field_key, permission) do
    not Map.has_key?(version.definition, "participants") and
      (actor.role != "parent" or
         (section["key"] == "application" and field_key == "document" and
            Enrollment.guardian?(actor, ticket.id))) and
      Policy.section?(actor, ticket, version, section, permission)
  end

  def reviewer?(actor, ticket, version, section) do
    Enrollment.staff?(actor) or
      (Instantflow.Collaboration.Assignments.assigned?(actor, ticket, version, section["key"]) and
         Policy.section?(actor, ticket, version, section, :edit))
  end
end
