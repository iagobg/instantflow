defmodule Instantflow.CuratedInvalidationTest do
  use Instantflow.DataCase, async: false
  alias Instantflow.{CuratedFixtures, Tenant, WorkflowCatalog, WorkflowFixtures, WorkflowRuntime}
  alias Instantflow.Delivery.{Attempt, Curated, Message}
  alias Instantflow.Diagnostics.QueryProbe
  alias Instantflow.Identity.{Membership, User}
  alias Instantflow.Participants.Relationship
  alias Instantflow.WorkflowRuntime.Notifications

  test "all historical recipients receive one signal across records and page boundaries" do
    f = CuratedFixtures.fixture("success")
    {:ok, release} = CuratedFixtures.release(f)
    first = Repo.get!(Message, release["message_id"])
    second_id = WorkflowFixtures.create_ticket(%{requester: f.clerk, version: f.version})
    {:ok, _} = WorkflowFixtures.save(f.clerk, second_id, %{"summary" => "Second snapshot"})

    for {operation, revision} <- [{"create", 0}, {"verify", 1}] do
      {:ok, _} =
        Instantflow.Participants.command(
          f.admin,
          Instantflow.BuilderFixtures.participant_command(
            second_id,
            f.recipient.id,
            operation,
            revision
          )
        )
    end

    {:ok, release} = CuratedFixtures.release(%{f | id: second_id})
    second = Repo.get!(Message, release["message_id"])
    members = historical_recipients(f, [first, second], 500)

    # A generic refresh is also needed to clear stale content after revocation.
    Repo.update_all(from(m in Membership, where: m.id == ^hd(members).id), set: [active: false])

    Repo.update_all(from(r in Relationship, where: r.membership_id == ^List.last(members).id),
      set: [status: "revoked", verified_at: nil, verified_by_id: nil]
    )

    for member <- [f.recipient | members],
        do: Phoenix.PubSub.subscribe(Instantflow.PubSub, "organization:1:user:#{member.user_id}")

    report =
      measure(fn ->
        Curated.invalidate(1, [first.ticket_id, second.ticket_id, first.ticket_id])
      end)

    assert report.statements == 3
    assert report.rows == 501
    assert report.errors == 0
    for _ <- 1..501, do: assert_receive(:communications_changed)
    refute_receive :communications_changed
  end

  test "workflows without communications add no curated lookup to list invalidation" do
    f = WorkflowFixtures.workflow_fixture()
    id = WorkflowFixtures.create_ticket(f)
    lists = measure(fn -> WorkflowRuntime.invalidate_lists(1, [id]) end)
    all = measure(fn -> Notifications.invalidate_recipients(1, [id]) end)
    assert all.statements == lists.statements
  end

  test "an older communications version still invalidates after a core-only publication" do
    f = CuratedFixtures.fixture("success")
    {:ok, _} = CuratedFixtures.release(f)

    definition =
      WorkflowFixtures.definition_fixture()
      |> Map.put("template_key", f.version.definition["template_key"])

    bindings = %{
      "roles" => %{"requester" => ["staff"], "reviewer" => ["admin"]},
      "departments" => %{"review_department" => f.admin.department_id}
    }

    {:ok, latest} = WorkflowCatalog.publish(f.admin, definition, bindings, f.version.number)
    core_id = WorkflowFixtures.create_ticket(%{requester: f.clerk, version: latest})
    Phoenix.PubSub.subscribe(Instantflow.PubSub, "organization:1:user:#{f.recipient.user_id}")

    measure(fn -> Notifications.invalidate_recipients(1, [core_id]) end)
    refute_receive :communications_changed
    measure(fn -> Notifications.invalidate_recipients(1, [core_id, f.id]) end)
    assert_receive :communications_changed
    refute_receive :communications_changed
  end

  defp measure(fun) do
    {:ok, {_, report}} =
      Tenant.raw(1, fn ->
        Tenant.authorization_gate!(1)
        QueryProbe.capture(fun)
      end)

    report
  end

  # Bulk historical audience fixture; ordinary release, delivery and revocation
  # paths are exercised with real commands above and in the LiveView tests.
  defp historical_recipients(f, messages, count) do
    now = DateTime.utc_now(:second)

    users =
      for n <- 1..count,
          do: %{
            email: "fanout-#{n}-#{Ecto.UUID.generate()}@example.test",
            name: "Synthetic",
            password_hash: f.admin.user.password_hash,
            inserted_at: now,
            updated_at: now
          }

    {_, users} = Repo.insert_all(User, users, returning: [:id])

    rows =
      for %{id: id} <- users,
          do: %{
            organization_id: 1,
            department_id: f.admin.department_id,
            user_id: id,
            role: "external",
            inserted_at: now,
            updated_at: now
          }

    {_, members} = Repo.insert_all(Membership, rows, returning: [:id, :user_id])

    for message <- messages do
      rows =
        for member <- members,
            do: %{
              organization_id: 1,
              workflow_id: f.version.workflow_id,
              ticket_id: message.ticket_id,
              membership_id: member.id,
              relationship: "claimant",
              status: "verified",
              revision: 2,
              verified_by_id: f.admin.user_id,
              verified_at: now,
              inserted_at: now,
              updated_at: now
            }

      {_, relationships} = Repo.insert_all(Relationship, rows, returning: [:id, :membership_id])
      relationships = Map.new(relationships, &{&1.membership_id, &1.id})

      rows =
        for member <- members,
            do: %{
              organization_id: 1,
              ticket_id: message.ticket_id,
              event_id: message.event_id,
              key: "historical:#{message.id}:#{member.id}",
              kind: message.kind,
              behavior: message.behavior,
              status: "succeeded",
              attempts: 1,
              recipient_membership_id: member.id,
              authorized_membership_id: f.admin.id,
              payload:
                Map.put(message.payload, "relationship_id", Map.fetch!(relationships, member.id)),
              inserted_at: now,
              updated_at: now
            }

      {_, releases} = Repo.insert_all(Message, rows, returning: [:id])

      Repo.insert_all(
        Attempt,
        for(
          m <- releases,
          do: %{
            organization_id: 1,
            outbox_message_id: m.id,
            number: 1,
            result: "succeeded",
            inserted_at: now,
            updated_at: now
          }
        )
      )
    end

    members
  end
end
