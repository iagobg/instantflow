defmodule Instantflow.PrivateDocuments.Policy do
  @moduledoc "Pinned, field-declared document permissions over current section/relationship authority."
  alias Instantflow.WorkflowRuntime.Policy, as: RecordPolicy

  def declaration(section, key) do
    field = Enum.find(section["fields"], &(&1["key"] == key))
    field && field["document_policy"]
  end

  def allowed?(actor, ticket, version, section, field, permission) do
    not is_nil(declaration(section, field)) and
      RecordPolicy.section?(actor, ticket, version, section, permission)
  end

  def download_allowed?(actor, ticket, version, section, field) do
    allowed?(actor, ticket, version, section, field, :read) and
      Instantflow.WorkflowRuntime.ParticipantPolicy.document_released?(
        actor,
        ticket,
        version,
        section["key"],
        field
      )
  end

  def reviewer?(actor, ticket, version, section, field, uploader) do
    case declaration(section, field) do
      nil ->
        false

      policy ->
        actor.user_id != uploader and
          Enum.any?(policy["reviewers"], &RecordPolicy.actor?(actor, ticket, version, &1))
    end
  end

  def file?(section, field, type, size) do
    case declaration(section, field) do
      nil -> false
      policy -> type in policy["media_types"] and size <= policy["max_bytes"]
    end
  end
end
