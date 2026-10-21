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
end
