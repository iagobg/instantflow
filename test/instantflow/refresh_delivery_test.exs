defmodule Instantflow.RefreshDeliveryTest do
  use Instantflow.DataCase, async: true
  import Ecto.Query
  import Instantflow.WorkflowFixtures
  alias Instantflow.{Delivery, Repo, Tenant, WorkflowRuntime}
  alias Instantflow.Delivery.{Attempt, Message}
  alias Instantflow.WorkflowRuntime.Ticket

  test "a business burst invalidates latest state once while preserving every durable attempt" do
    f = workflow_fixture()
    id = create_ticket(f)
    assert {:ok, _} = save(f.requester, id, values())
    assert {:ok, _} = save(f.requester, id, Map.put(values(), "summary", "Revisão mais recente"))
    Phoenix.PubSub.subscribe(Instantflow.PubSub, Delivery.topic(f.requester.organization_id, id))
    ids = Delivery.pending_ids(f.requester.organization_id)
    assert length(ids) == 3
    Delivery.drain()
    assert_receive {:ticket_changed, 1, ^id}
    refute_receive {:ticket_changed, 1, ^id}
    assert Repo.aggregate(Attempt, :count) == 3
    assert Repo.aggregate(from(m in Message, where: m.status == "succeeded"), :count) == 3

    assert {:ok, %{ticket: %{revision: 3, refreshed_revision: 3}}} =
             WorkflowRuntime.get(f.requester, id)

    assert {:ok, :already_processed} = Delivery.process(f.requester.organization_id, hd(ids))
    assert {:ok, _} = save(f.requester, id, Map.put(values(), "summary", "Nova revisão"))
    [next] = Delivery.pending_ids(f.requester.organization_id)
    Delivery.process(f.requester.organization_id, next)
    assert_receive {:ticket_changed, 1, ^id}
  end

  test "rollback after notification cannot lose the durable refresh checkpoint or retry" do
    f = workflow_fixture()
    id = create_ticket(f)
    [message] = Delivery.pending_ids(f.requester.organization_id)
    Phoenix.PubSub.subscribe(Instantflow.PubSub, Delivery.topic(f.requester.organization_id, id))

    assert {:error, :crash} =
             Repo.transaction(fn ->
               Delivery.process(f.requester.organization_id, message)
               Repo.rollback(:crash)
             end)

    assert_receive {:ticket_changed, 1, ^id}
    assert Repo.get!(Ticket, id).refreshed_revision == 0
    assert Repo.aggregate(Attempt, :count) == 0
    assert {:ok, _} = Delivery.process(f.requester.organization_id, message)
    assert_receive {:ticket_changed, 1, ^id}
    assert Repo.get!(Ticket, id).refreshed_revision == 1
    assert Repo.aggregate(Attempt, :count) == 1
  end

  test "a multi-record batch notifies each list recipient once and retains every attempt" do
    f = workflow_fixture()
    ids = for _ <- 1..3, do: create_ticket(f)
    for id <- ids, do: assert({:ok, _} = save(f.requester, id, values()))
    Phoenix.PubSub.subscribe(Instantflow.PubSub, WorkflowRuntime.list_topic(f.reviewer))
    for id <- ids, do: Phoenix.PubSub.subscribe(Instantflow.PubSub, Delivery.topic(1, id))

    assert [{1, {:ok, 6}}] = Delivery.drain()
    assert_receive :requests_changed
    refute_receive :requests_changed

    for id <- ids do
      assert_receive {:ticket_changed, 1, ^id}
      refute_receive {:ticket_changed, 1, ^id}
      assert %{revision: 2, refreshed_revision: 2} = Repo.get!(Ticket, id)
    end

    assert Repo.aggregate(Attempt, :count) == 6
    assert Delivery.pending_ids(1) == []
  end

  test "a rolled-back batch retries every checkpoint and recipient without retained state" do
    f = workflow_fixture()
    ids = for _ <- 1..2, do: create_ticket(f)
    Phoenix.PubSub.subscribe(Instantflow.PubSub, WorkflowRuntime.list_topic(f.requester))

    assert {:error, :crash} =
             Repo.transaction(fn ->
               Delivery.drain()
               Repo.rollback(:crash)
             end)

    assert_receive :requests_changed
    refute_receive :requests_changed
    assert Repo.aggregate(Attempt, :count) == 0
    for id <- ids, do: assert(Repo.get!(Ticket, id).refreshed_revision == 0)

    assert [{1, {:ok, 2}}] = Delivery.drain()
    assert_receive :requests_changed
    refute_receive :requests_changed
    assert Repo.aggregate(Attempt, :count) == 2
    for id <- ids, do: assert(Repo.get!(Ticket, id).refreshed_revision == 1)
  end

  test "simulation results still invalidate when the business revision is unchanged" do
    f = workflow_fixture()
    id = create_ticket(f)
    save(f.requester, id, values())
    transition(f.requester, id, "submit")
    Phoenix.PubSub.subscribe(Instantflow.PubSub, Delivery.topic(f.requester.organization_id, id))
    Delivery.drain()
    assert_receive {:ticket_changed, 1, ^id}
    {:ok, data} = WorkflowRuntime.get(f.reviewer, id)
    assert Enum.any?(data.deliveries, &(&1.status == "failed"))
    revision = data.ticket.revision
    Delivery.drain()
    assert_receive {:ticket_changed, 1, ^id}

    assert {:ok, %{ticket: %{revision: ^revision, refreshed_revision: ^revision}}} =
             WorkflowRuntime.get(f.reviewer, id)

    assert {:ok, 0} =
             Tenant.transaction(f.reviewer, fn _ ->
               Repo.aggregate(from(m in Message, where: m.status == "pending"), :count)
             end)
  end

  test "multiple outcome refreshes notify once without advancing a record checkpoint" do
    f = workflow_fixture()
    id = create_ticket(f)
    Delivery.drain()
    before = Repo.get!(Ticket, id)
    event_id = Repo.get_by!(Message, ticket_id: id).event_id
    Phoenix.PubSub.subscribe(Instantflow.PubSub, Delivery.topic(1, id))
    Phoenix.PubSub.subscribe(Instantflow.PubSub, WorkflowRuntime.list_topic(f.reviewer))

    for n <- 1..2 do
      Repo.insert!(%Message{
        organization_id: 1,
        ticket_id: id,
        event_id: event_id,
        key: "delivery-result:synthetic:#{n}",
        kind: "refresh"
      })
    end

    assert [{1, {:ok, 2}}] = Delivery.drain()
    assert_receive {:ticket_changed, 1, ^id}
    assert_receive :requests_changed
    refute_receive {:ticket_changed, 1, ^id}
    refute_receive :requests_changed
    assert Repo.get!(Ticket, id) == before
    assert Repo.aggregate(Attempt, :count) == 3
  end
end
