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
      refute source =~ "template_key"
    end

    view = File.read!(Path.join(root, "instantflow_web/live/participant_live.ex"))
    refute view =~ "Repo."
  end
end
