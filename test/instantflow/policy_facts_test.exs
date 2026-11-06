defmodule Instantflow.PolicyFactsTest do
  use Instantflow.DataCase, async: true

  alias Instantflow.{
    Access,
    BuilderFixtures,
    DocumentHistoryFixtures,
    IncidentFixtures,
    Participants,
    Tenant,
    WorkflowRuntime
  }

  alias Instantflow.WorkflowRuntime.{Policy, RecordProjection, RecordRead}
  alias Instantflow.QuerySourceProbe

  test "participant projections load relationships once and observe subsequent revocation" do
    f = DocumentHistoryFixtures.fixture(1)

    {{:ok, projection}, counts} =
      QuerySourceProbe.capture(["ticket_participants"], fn ->
        RecordProjection.load(f.visitor, f.ticket_id)
      end)

    assert counts["ticket_participants"] == 1
    assert "customer_details" in projection.data.editable
    assert projection.documents.rows != []
    assert_policy_parity(f.visitor, f.ticket_id)

    assert {:ok, _} =
             Participants.command(
               f.admin,
               BuilderFixtures.participant_command(f.ticket_id, f.visitor.id, "revoke", 2)
             )

    assert {:error, :not_found} = RecordProjection.load(f.visitor, f.ticket_id)
  end

  test "named assignment facts are shared and never survive reassignment or grant revocation" do
    f = IncidentFixtures.incident_fixture()
    id = IncidentFixtures.report(f)
    IncidentFixtures.followup(f, id)

    {{:ok, projection}, counts} =
      QuerySourceProbe.capture(["section_assignments"], fn ->
        RecordProjection.load(f.counselor, id)
      end)

    assert counts["section_assignments"] == 1
    assert "support" in projection.data.editable
    assert_policy_parity(f.counselor, id)
    assert_policy_parity(f.dean, id)
    assert {:ok, _} = IncidentFixtures.assign(f.dean, id, f.other_counselor.id, "Reassign")
    assert {:error, :not_found} = RecordProjection.load(f.counselor, id)
    assert {:ok, next} = RecordProjection.load(f.other_counselor, id)
    assert "support" in next.data.editable
    grant = Enum.find(f.other_counselor.grants, &(&1.role == "counselor"))
    assert {:ok, _} = Access.revoke(f.admin, grant.id)
    assert {:error, :not_found} = RecordProjection.load(f.other_counselor, id)
  end

  defp assert_policy_parity(actor, id) do
    context =
      Tenant.read_context(actor, fn context ->
        fresh = Tenant.context_scope!(context)
        {ticket, version} = RecordRead.fetch!(context, id)
        facts = RecordRead.facts!(context, id)

        for section <- version.definition["sections"], action <- [:read, :edit] do
          assert Policy.section?(fresh, ticket, version, section, action, facts) ==
                   Policy.section?(fresh, ticket, version, section, action)
        end

        for edge <- version.definition["transitions"] do
          assert Policy.transition?(fresh, ticket, version, edge, facts) ==
                   Policy.transition?(fresh, ticket, version, edge)
        end

        events = Repo.all(from e in WorkflowRuntime.Event, where: e.ticket_id == ^id)

        for event <- events do
          assert Policy.history?(fresh, ticket, version, event, facts) ==
                   Policy.history?(fresh, ticket, version, event)
        end

        assert Policy.retry?(fresh, ticket, version, facts) ==
                 Policy.retry?(fresh, ticket, version)

        context
      end)

    assert_raise ArgumentError, fn -> RecordRead.facts!(context, id) end
  end
end
