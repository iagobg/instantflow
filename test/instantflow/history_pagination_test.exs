defmodule Instantflow.HistoryPaginationTest do
  use Instantflow.DataCase, async: true
  import Instantflow.WorkflowFixtures
  import Instantflow.CollaborationFixtures
  alias Instantflow.{HistoryFixtures, Tenant, WorkflowRuntime}
  alias Instantflow.WorkflowRuntime.{Event, History, Policy, Ticket}
  alias Instantflow.Diagnostics.QueryProbe

  test "first page stays bounded at 1, 1001 and 10001 events and uses pinned visibility" do
    f = collaborative_fixture()
    id = create_ticket(f)
    {:ok, initial} = WorkflowRuntime.get(f.requester, id)
    assert length(initial.events) == 1

    for {revisions, label} <- [{2..1001, "history_1001"}, {1002..10001, "history_10001"}] do
      HistoryFixtures.append(f.requester, id, revisions)
      {{:ok, page}, report} = QueryProbe.capture(fn -> WorkflowRuntime.get(f.requester, id) end)
      assert length(page.events) == 50
      assert report.groups.history.rows == 51
      assert page.history_next_cursor == Enum.max(revisions) - 49

      if path = System.get_env("DB_EFFICIENCY_REPORT"),
        do: File.write!(path, Jason.encode!(Map.put(report, :scenario, label)) <> "\n", [:append])
    end

    # A later publication changes access, but existing records keep their definition.
    changed =
      put_in(
        f.definition,
        ["sections", Access.at(0), "access"],
        Enum.at(f.definition["sections"], 2)["access"]
      )

    assert {:ok, _} =
             Instantflow.WorkflowCatalog.publish(f.admin, changed, f.bindings, f.version.number)

    assert {:ok, pinned} = WorkflowRuntime.get(f.requester, id)
    assert hd(pinned.events).operation == "save:request"
    assert pinned.ticket.workflow_version_id == f.version.id
  end

  test "hidden newer history cannot consume a page and appends do not duplicate older pages" do
    f = collaborative_fixture()
    id = create_ticket(f)
    HistoryFixtures.append(f.requester, id, 2..103)
    HistoryFixtures.append(f.requester, id, 104..203, "save:finance")
    {:ok, first} = WorkflowRuntime.get(f.requester, id)
    assert Enum.map(first.events, & &1.revision) == Enum.to_list(103..54//-1)
    HistoryFixtures.append(f.requester, id, 204..204)

    {:ok, second} =
      WorkflowRuntime.get(f.requester, id, history_before: first.history_next_cursor)

    assert Enum.map(second.events, & &1.revision) == Enum.to_list(53..4//-1)
    {:ok, last} = WorkflowRuntime.get(f.requester, id, history_before: second.history_next_cursor)
    assert Enum.map(last.events, & &1.revision) == [3, 2, 1]
    assert last.history_next_cursor == nil

    for cursor <- ["54", -1, 0, 2_147_483_648, 9_223_372_036_854_775_807] do
      {:ok, invalid} = WorkflowRuntime.get(f.requester, id, history_before: cursor)
      assert invalid.events == []
      assert invalid.history_next_cursor == nil
    end
  end

  test "SQL history predicate matches policy for sections, transitions and malformed operations" do
    f = collaborative_fixture()
    id = create_ticket(f)

    operations =
      ~w(save:request save:finance save:unknown assign:request assign:unknown create approve
      participant:create:claimant participant:create:claimant:extra participant:bad
      document:upload:request.proof document:old:request document:old:finance.proof
      document:bad release:unknown unknown)

    for {operation, revision} <- Enum.with_index(operations, 2),
        do: HistoryFixtures.append(f.requester, id, revision..revision, operation)

    Tenant.read(f.requester, fn actor ->
      ticket = Repo.get!(Ticket, id)

      expected =
        Repo.all(from e in Event, where: e.ticket_id == ^id)
        |> Enum.filter(&Policy.history?(actor, ticket, f.version, &1))
        |> Enum.map(& &1.id)
        |> Enum.sort()

      actual =
        History.authorized_query(actor, ticket, f.version)
        |> Repo.all()
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert actual == expected
    end)
  end

  test "delivery pages are independently authorized and older failures remain retryable" do
    f = collaborative_fixture()
    id = create_ticket(f)
    events = HistoryFixtures.append(f.requester, id, 2..103)
    messages = HistoryFixtures.deliveries(events)
    hidden = HistoryFixtures.append(f.requester, id, 104..203, "save:finance")
    [hidden_message | _] = HistoryFixtures.deliveries(hidden)
    {:ok, page} = WorkflowRuntime.get(f.reviewer, id)
    assert length(page.deliveries) == 50

    assert Enum.map(page.deliveries, & &1.id) ==
             messages |> Enum.reverse() |> Enum.take(50) |> Enum.map(& &1.id)

    {:ok, older} =
      WorkflowRuntime.get(f.reviewer, id, deliveries_before: page.deliveries_next_cursor)

    assert length(older.deliveries) == 50

    {:ok, last} =
      WorkflowRuntime.get(f.reviewer, id, deliveries_before: older.deliveries_next_cursor)

    assert length(last.deliveries) == 2
    assert last.deliveries_next_cursor == nil
    assert {:ok, _} = Instantflow.Delivery.retry(f.reviewer, hd(messages).id)
    assert {:error, :forbidden} = Instantflow.Delivery.retry(f.reviewer, hidden_message.id)
  end
end
