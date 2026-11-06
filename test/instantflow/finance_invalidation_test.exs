defmodule Instantflow.FinanceInvalidationTest do
  use Instantflow.DataCase, async: true
  import Instantflow.WorkflowFixtures
  alias Instantflow.{Delivery, Finance, WorkflowCatalog}

  test "core-only batch and single-message delivery preserve record refresh without budget publication" do
    f = workflow_fixture()
    id = create_ticket(f)
    Phoenix.PubSub.subscribe(Instantflow.PubSub, Finance.topic(1))
    Phoenix.PubSub.subscribe(Instantflow.PubSub, Delivery.topic(1, id))
    Delivery.drain()
    assert_receive {:ticket_changed, 1, ^id}
    refute_receive :budgets_changed

    assert {:ok, _} = save(f.requester, id, values())
    [pending] = Delivery.pending_ids(1)
    assert {:ok, _} = Delivery.process(1, pending)
    assert_receive {:ticket_changed, 1, ^id}
    refute_receive :budgets_changed
  end

  test "finance publication follows pinned versions and is deduplicated across a mixed batch" do
    f = workflow_fixture()
    core_id = create_ticket(f)
    definition = Map.put(f.definition, "capabilities", ["core", "finance"])

    {:ok, finance_version} =
      WorkflowCatalog.publish(f.admin, definition, f.bindings, f.version.number)

    Phoenix.PubSub.subscribe(Instantflow.PubSub, Finance.topic(1))

    # A newer finance version cannot make the old core record financial.
    Delivery.drain()
    refute_receive :budgets_changed

    finance_ids = for _ <- 1..2, do: create_ticket(%{f | version: finance_version})

    {:ok, core_version} =
      WorkflowCatalog.publish(f.admin, f.definition, f.bindings, finance_version.number)

    latest_id = create_ticket(%{f | version: core_version})

    # Removing finance from the latest version cannot suppress older records.
    assert [{1, {:ok, 3}}] = Delivery.drain()
    assert_receive :budgets_changed
    refute_receive :budgets_changed

    for id <- [core_id, latest_id | finance_ids] do
      assert Repo.get!(Instantflow.WorkflowRuntime.Ticket, id).refreshed_revision == 1
    end
  end
end
