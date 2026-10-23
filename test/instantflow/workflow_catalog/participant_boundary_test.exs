defmodule Instantflow.WorkflowCatalog.ParticipantBoundaryTest do
  use ExUnit.Case, async: true

  test "participant contracts stay pure and generated surfaces do not dispatch to examples" do
    root = Path.expand("../../../lib", __DIR__)
    catalog = File.read!(Path.join(root, "instantflow/workflow_catalog/participant_pages.ex"))
    refute catalog =~ ~r/\b(Repo|Tenant)\.|WorkflowRuntime\./

    for path <-
          ~w(instantflow/workflow_runtime/participant_pages.ex instantflow/workflow_runtime/participant_policy.ex instantflow/workflow_runtime/projections.ex instantflow_web/live/participant_live.ex) do
      source = File.read!(Path.join(root, path))
      # Document is the documented legacy storage-schema alias, not a service.
      refute source =~ ~r/Instantflow\.(Enrollment|Incidents)\.(?!Document\b)/
      refute source =~ "EnrollmentLive"
      # Policy-only metadata may discard portable identity fields in SQL. Permit
      # only that subtraction; reads/branches on example identity remain forbidden.
      metadata_omission =
        "? - ARRAY['stages','transitions','description','role_requirements','bindings','format_version','template_key','template_version','locale']::text[]"

      refute String.replace(source, metadata_omission, "?") =~ "template_key"
    end

    view = File.read!(Path.join(root, "instantflow_web/live/participant_live.ex"))
    refute view =~ "Repo."
  end

  test "shared generated components render projections without reading or mutating contexts" do
    root = Path.expand("../../../lib/instantflow_web/components", __DIR__)

    for name <- ~w(layouts process_components field_input pagination_controls authoring_panels) do
      source = File.read!(Path.join(root, name <> ".ex"))
      refute source =~ ~r/\b(Repo|Tenant)\./
      refute source =~ ~r/Workspaces\.(navigation|installed|get|search)/
      refute source =~ ~r/(WorkflowRuntime|Operations)\.(command|workspace|visit|search|get)\(/
    end
  end
end
