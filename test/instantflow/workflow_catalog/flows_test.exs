defmodule Instantflow.WorkflowCatalog.FlowsTest do
  use Instantflow.DataCase, async: true
  import Instantflow.WorkflowFixtures
  alias Instantflow.{WorkflowCatalog, WorkflowRuntime}
  alias Instantflow.WorkflowCatalog.{Flows, Templates, Version}

  test "flow is a structural allowlist, with actor-private paths omitted from the overview" do
    f = workflow_fixture()

    definition =
      Map.update!(f.definition, "transitions", fn transitions ->
        Enum.map(transitions, fn edge ->
          if edge["key"] == "approve",
            do:
              Map.merge(edge, %{"history_visibility" => "actors", "disallow_requester" => true}),
            else: edge
        end)
      end)

    {:ok, version} = WorkflowCatalog.publish(f.admin, definition, f.bindings, 1)
    id = create_ticket(%{f | version: version})
    assert {:ok, overview} = Flows.get(f.requester, version.workflow_id)
    assert Map.keys(overview.definition) |> Enum.sort() == ["stages", "transitions"]

    assert Enum.all?(
             overview.definition["stages"],
             &(Map.keys(&1) |> Enum.sort() == ~w(initial key label terminal))
           )

    assert Enum.all?(
             overview.definition["transitions"],
             &(Map.keys(&1) |> Enum.sort() == ~w(from key kind label to))
           )

    refute Enum.any?(overview.definition["transitions"], &(&1["key"] == "approve"))
    refute Map.has_key?(overview, :bindings)
    assert {:ok, requester} = Flows.get(f.requester, version.workflow_id, id)
    refute Enum.any?(requester.definition["transitions"], &(&1["key"] == "approve"))
    assert {:ok, reviewer} = Flows.get(f.reviewer, version.workflow_id, id)
    assert Enum.any?(reviewer.definition["transitions"], &(&1["key"] == "approve"))
    refute requester.can_author?
    assert {:ok, %{can_author?: true}} = Flows.get(f.admin, version.workflow_id)
  end

  test "records retain their pin after newer publication, draft edits and archival" do
    f = workflow_fixture()
    id = create_ticket(f)
    definition = put_in(f.definition, ["stages", Access.at(0), "label"], "Nova recepção")
    {:ok, version} = WorkflowCatalog.publish(f.admin, definition, f.bindings, 1)
    {:ok, draft} = Templates.clone(f.admin, version.id)

    draft_definition =
      put_in(definition, ["stages", Access.at(0), "label"], "Rascunho ainda não publicado")

    assert {:ok, _} =
             Templates.save(f.admin, draft.id, draft.revision, draft_definition, draft.bindings)

    assert {:ok, current} = Flows.get(f.requester, version.workflow_id)
    assert current.number == 2
    assert hd(current.definition["stages"])["label"] == "Nova recepção"
    assert {:ok, pinned} = Flows.get(f.requester, version.workflow_id, id)
    assert pinned.version_id == f.version.id
    assert pinned.number == 1
    assert pinned.current_stage == "draft"

    assert pinned.definition["stages"] ==
             Enum.map(f.definition["stages"], &Map.take(&1, ~w(key label initial terminal)))

    Repo.insert_all("retired_workflow_versions", [
      %{
        version_id: f.version.id,
        organization_id: f.admin.organization_id,
        reason: "Flow archival acceptance",
        inserted_at: DateTime.utc_now(:second)
      }
    ])

    assert {:ok, %{archived?: true, number: 1}} = Flows.get(f.requester, version.workflow_id, id)
    assert Repo.get!(Version, f.version.id).definition == f.definition
  end

  test "confidential cases require explicit discovery; administrator and unassigned counselor are denied" do
    f = Instantflow.IncidentFixtures.incident_fixture()
    id = Instantflow.IncidentFixtures.report(f)
    assert {:error, :not_found} = Flows.get(f.admin, f.version.workflow_id)

    for actor <- [f.admin, f.other_counselor] do
      assert {:error, :not_found} = Flows.get(actor, f.version.workflow_id, id)
    end

    assert {:ok, _} = Flows.get(f.dean, f.version.workflow_id, id)
    assert {:error, :not_found} = Flows.get(f.teacher, f.version.workflow_id + 1000, id)
    assert {:error, :not_found} = Flows.get(f.teacher, nil, id)
    assert {:error, :not_found} = Flows.get(nil, f.version.workflow_id, id)
  end

  test "participant audiences and organization switches cannot bypass the curated record projection" do
    f = Instantflow.EnrollmentFixtures.enrollment_fixture()
    assert {:error, :not_found} = Flows.get(f.parent, f.version.workflow_id, f.enrollment.id)
    b = Instantflow.EnrollmentFixtures.second_school(f)
    assert {:error, :not_found} = Flows.get(b.admin, f.version.workflow_id)
    assert {:error, :not_found} = Flows.get(b.admin, f.version.workflow_id, f.enrollment.id)
    assert {:ok, _} = WorkflowRuntime.get(f.admin, f.enrollment.id)
  end
end
