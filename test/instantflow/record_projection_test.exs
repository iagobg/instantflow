defmodule Instantflow.RecordProjectionTest do
  use Instantflow.DataCase, async: true
  import Instantflow.WorkflowFixtures
  import Instantflow.CollaborationFixtures
  alias Instantflow.{Access, Identity, Participants, PrivateDocuments, Tenant, WorkflowRuntime}
  alias Instantflow.Collaboration.Presence
  alias Instantflow.Delivery.Curated
  alias Instantflow.Diagnostics.QueryProbe
  alias Instantflow.WorkflowRuntime.{RecordProjection, RecordRead}

  test "record projection keeps public read policy parity with one authorization load" do
    f = collaborative_fixture()
    id = create_ticket(f)

    for actor <- [f.requester, f.reviewer] do
      {:ok, expected} = WorkflowRuntime.get(actor, id)
      {{:ok, projection}, report} = QueryProbe.capture(fn -> RecordProjection.load(actor, id) end)

      assert projection.data == expected
      assert projection.management == Participants.controls(actor, id)
      assert projection.communications == Curated.controls_for(actor, id)
      assert projection.documents == PrivateDocuments.list_page(actor, id)
      assert projection.presence == Presence.editors(actor, expected)
      assert report.groups.authorization.statements == 3
      assert report.content_selections == 0
      assert report.errors == 0
    end

    assert {:error, :not_found} = RecordProjection.load(f.admin, id)
  end

  test "composite reads reauthorize grants and membership instead of retaining old projections" do
    f = collaborative_fixture()
    id = create_ticket(f)
    {:ok, {_, grant}} = Access.grant(f.admin, f.reviewer.id, f.reviewer.department_id, "finance")
    {:ok, visible} = RecordProjection.load(f.reviewer, id)
    assert "finance" in visible.data.editable

    Repo.delete!(grant)
    {:ok, revoked} = RecordProjection.load(f.reviewer, id)
    refute "finance" in revoked.data.editable
    refute Enum.any?(revoked.data.sections, &(&1.key == "finance"))
    assert {:ok, _} = Identity.revoke(f.admin, f.reviewer.id)
    assert {:error, :not_found} = RecordProjection.load(f.reviewer, id)
  end

  test "record cache does not bleed across records or accept an expired context" do
    f = workflow_fixture()
    first = create_ticket(f)
    second = create_ticket(f)

    context =
      Tenant.read_context(f.requester, fn context ->
        {a, _} = RecordRead.fetch!(context, first)
        {b, _} = RecordRead.fetch!(context, second)
        assert a.id == first
        assert b.id == second
        {{^a, _}, repeated} = QueryProbe.capture(fn -> RecordRead.fetch!(context, first) end)
        assert repeated.statements == 0
        context
      end)

    for read <- [
          fn -> WorkflowRuntime.get_in_context(context, first) end,
          fn -> Participants.controls_in_context(context, first, "") end,
          fn -> Curated.controls_in_context(context, first, "") end,
          fn -> PrivateDocuments.list_page_in_context(context, first, nil) end,
          fn -> Presence.editors_in_context(context, first) end
        ] do
      assert_raise ArgumentError, read
    end
  end

  test "missing records fail closed and do not poison a later projection" do
    f = workflow_fixture()
    id = create_ticket(f)
    assert {:error, :not_found} = RecordProjection.load(f.requester, 9_000_000)
    assert {:ok, %{data: %{ticket: %{id: ^id}}}} = RecordProjection.load(f.requester, id)
  end
end
