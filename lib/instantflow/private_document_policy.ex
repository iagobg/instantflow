defmodule Instantflow.PrivateDocuments.Policy do
  @moduledoc "Pinned, field-declared document permissions over current section/relationship authority."
  alias Instantflow.PrivateDocuments.LegacyPolicy
  alias Instantflow.WorkflowRuntime.Policy, as: RecordPolicy

  def declaration(section, key) do
    field = Enum.find(section["fields"], &(&1["key"] == key))
    field && field["document_policy"]
  end

  def allowed?(actor, ticket, version, section, field, permission) do
    if declaration(section, field),
      do: RecordPolicy.section?(actor, ticket, version, section, permission),
      else: LegacyPolicy.allowed?(actor, ticket, version, section, field, permission)
  end

  def reviewer?(actor, ticket, version, section, field, uploader) do
    case declaration(section, field) do
      nil ->
        LegacyPolicy.reviewer?(actor, ticket, version, section)

      policy ->
        actor.user_id != uploader and
          Enum.any?(policy["reviewers"], &RecordPolicy.actor?(actor, ticket, version, &1))
    end
  end

  def file?(section, field, type, size) do
    case declaration(section, field) do
      nil -> true
      policy -> type in policy["media_types"] and size <= policy["max_bytes"]
    end
  end
end
