defmodule Instantflow.ListInvalidationEfficiencyTest do
  use Instantflow.DataCase, async: false
  import Instantflow.WorkflowFixtures

  alias Instantflow.{
    BuilderFixtures,
    DocumentHistoryFixtures,
    Participants,
    Tenant,
    WorkflowRuntime
  }

  alias Instantflow.Diagnostics.QueryProbe
  alias Instantflow.Identity.{Membership, User}

  test "recipient query count grows by batches instead of individual memberships" do
    f = workflow_fixture()
    id = create_ticket(f)
    assert Repo.aggregate(Membership, :count) == 3
    small = measure("invalidation_3_members", id)
    ids = [id | for(_ <- 1..19, do: create_ticket(f))]
    assert measure("invalidation_20_records_3_members", ids).statements == small.statements
    add_members(f, 1..100)
    medium = measure("invalidation_103_members", id)
    assert medium.statements == small.statements
    add_members(f, 101..1000)
    large = measure("invalidation_1003_members", id)
    assert large.statements <= small.statements + 8
    assert large.errors == 0
    assert measure("invalidation_20_records_1003_members", ids).statements == large.statements
  end

  test "batch recipients are the union of current access under each pinned version" do
    f = workflow_fixture()
    first = create_ticket(f)
    bindings = Map.put(f.bindings, "roles", %{"requester" => ["admin"], "reviewer" => ["admin"]})

    {:ok, latest} =
      Instantflow.WorkflowCatalog.publish(f.admin, f.definition, bindings, f.version.number)

    second = create_ticket(%{f | requester: f.admin, version: latest})

    assert {:ok, _} = WorkflowRuntime.get(f.reviewer, first)
    assert {:error, :not_found} = WorkflowRuntime.get(f.reviewer, second)
    assert_notification(f.reviewer, [first, second], true)
    assert_notification(f.admin, [first, second], true)

    Repo.update_all(from(u in User, where: u.id == ^f.reviewer.user_id), set: [active: false])
    assert_notification(f.reviewer, [first, second], false)
  end

  test "batched notifications agree with confidential assignment access, including reassignment" do
    f = Instantflow.IncidentFixtures.incident_fixture()
    id = Instantflow.IncidentFixtures.report(f)
    Instantflow.IncidentFixtures.followup(f, id)
    actors = [f.teacher, f.dean, f.counselor, f.other_counselor, f.admin]

    for actor <- actors do
      allowed = match?({:ok, _}, WorkflowRuntime.get(actor, id))
      assert_notification(actor, id, allowed)
    end

    assert {:ok, _} =
             Instantflow.IncidentFixtures.assign(f.dean, id, f.other_counselor.id, "Transfer")

    assert_notification(f.counselor, id, false)
    assert_notification(f.other_counselor, id, true)

    second = Instantflow.IncidentFixtures.report(f)
    Instantflow.IncidentFixtures.followup(f, second)
    assert_notification(f.counselor, [id, second], true)
    assert_notification(f.other_counselor, [id, second], true)
  end

  test "verified participants receive invalidations; revoked and inactive identities do not" do
    f = DocumentHistoryFixtures.fixture(1)
    assert_notification(f.visitor, f.ticket_id, true)

    assert {:ok, _} =
             Participants.command(
               f.admin,
               BuilderFixtures.participant_command(f.ticket_id, f.visitor.id, "revoke", 2)
             )

    assert_notification(f.visitor, f.ticket_id, false)
    Repo.update_all(from(u in User, where: u.id == ^f.clerk.user_id), set: [active: false])
    assert_notification(f.clerk, f.ticket_id, false)
  end

  defp assert_notification(actor, id, expected) do
    topic = WorkflowRuntime.list_topic(actor)
    Phoenix.PubSub.subscribe(Instantflow.PubSub, topic)

    try do
      assert {:ok, _} =
               Tenant.raw(actor.organization_id, fn ->
                 Tenant.authorization_gate!(actor.organization_id)
                 WorkflowRuntime.invalidate_lists(actor.organization_id, id)
               end)

      if expected, do: assert_receive(:requests_changed)
      refute_receive :requests_changed
    after
      Phoenix.PubSub.unsubscribe(Instantflow.PubSub, topic)
    end
  end

  defp measure(scenario, id) do
    {_, report} =
      QueryProbe.capture(fn ->
        Tenant.raw(1, fn -> WorkflowRuntime.invalidate_lists(1, id) end)
      end)

    if path = System.get_env("DB_EFFICIENCY_REPORT"),
      do:
        File.write!(path, Jason.encode!(Map.put(report, :scenario, scenario)) <> "\n", [:append])

    report
  end

  defp add_members(f, range) do
    for n <- range do
      user =
        Repo.insert!(%User{
          email: "notify-#{n}@synthetic.invalid",
          name: "Synthetic",
          password_hash: f.requester.user.password_hash
        })

      Repo.insert!(%Membership{
        organization_id: 1,
        user_id: user.id,
        department_id: f.reviewer.department_id,
        role: f.reviewer.role
      })
    end
  end
end
