defmodule InstantflowWeb.RefreshCoalescingLiveTest do
  use InstantflowWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  import Instantflow.WorkflowFixtures
  import Instantflow.CollaborationFixtures
  alias Instantflow.{Access, Delivery, Repo, WorkflowRuntime}
  alias Instantflow.Diagnostics.QueryProbe

  test "a queued mixed record burst performs one current refresh in each tab", %{conn: conn} do
    f = collaborative_fixture()
    id = create_ticket(f)
    {:ok, first, _} = live(login(conn, f.requester), ~p"/o/horizonte/solicitacoes/#{id}")
    {:ok, second, _} = live(login(build_conn(), f.requester), ~p"/o/horizonte/solicitacoes/#{id}")
    _ = render(first)
    _ = render(second)
    {_, one} = burst("record_single", first, [{:ticket_changed, 1, id}])

    messages =
      List.duplicate([{:ticket_changed, 1, id}, :reconcile, :permissions_changed], 10)
      |> List.flatten()

    {_, many} = burst("record_30_notifications", first, messages)
    {_, other_tab} = burst("record_30_notifications_second_tab", second, messages)
    assert many.statements == one.statements
    assert other_tab.statements == one.statements
    assert many.groups.history.statements == 1
  end

  test "delivery-only updates are refreshed without a ticket revision change", %{conn: conn} do
    f = workflow_fixture()
    id = create_ticket(f)
    assert {:ok, _} = save(f.requester, id, values())
    assert {:ok, _} = transition(f.requester, id, "submit")
    {:ok, before} = WorkflowRuntime.get(f.reviewer, id)
    message = Enum.find(before.deliveries, &(&1.kind == "simulate_notification"))
    {:ok, view, _} = live(login(conn, f.reviewer), ~p"/o/horizonte/solicitacoes/#{id}")
    assert {:ok, _} = Delivery.process(1, message.id)
    assert {:ok, after_delivery} = WorkflowRuntime.get(f.reviewer, id)
    assert before.ticket.revision == after_delivery.ticket.revision
    burst("delivery_same_revision", view, List.duplicate({:ticket_changed, 1, id}, 20))
    assert has_element?(view, "#retry-#{message.id}")
  end

  test "presence bursts keep their lightweight refresh and do not fetch history", %{conn: conn} do
    f = collaborative_fixture()
    id = create_ticket(f)
    {:ok, view, _} = live(login(conn, f.requester), ~p"/o/horizonte/solicitacoes/#{id}")

    message = %Phoenix.Socket.Broadcast{
      event: "presence_diff",
      topic: Instantflow.Collaboration.Presence.topic(1, id),
      payload: %{}
    }

    {_, one} = burst("presence_single", view, [message])
    {_, many} = burst("presence_30_notifications", view, List.duplicate(message, 30))
    assert many.statements == one.statements
    assert many.groups.history.statements == 0
    assert many.groups.documents.statements == 0
  end

  test "combined permission invalidation removes revoked values and preserves an unrelated draft",
       %{conn: conn} do
    f = collaborative_fixture()
    id = create_ticket(f)
    {:ok, {_, grant}} = Access.grant(f.admin, f.reviewer.id, f.reviewer.department_id, "finance")
    {:ok, view, _} = live(login(conn, f.reviewer), ~p"/o/horizonte/solicitacoes/#{id}")
    view |> form("#section-form-finance", section: %{summary: "Private draft"}) |> render_change()
    view |> form("#section-form-notes", section: %{summary: "Keep this"}) |> render_change()
    Repo.delete!(grant)

    burst("permission_and_record", view, [
      {:ticket_changed, 1, id},
      :permissions_changed,
      :reconcile
    ])

    refute has_element?(view, "#section-form-finance")
    assert has_element?(view, "#section-form-notes input[value='Keep this']")
  end

  test "queued operational invalidations share a refresh", %{conn: conn} do
    f = Instantflow.OperationsFixtures.operations_fixture()

    version =
      Instantflow.Operations.workspace(f.actor, Instantflow.Operations.today(f.actor)).version

    {:ok, view, _} = live(login(conn, f.actor), ~p"/o/horizonte/processos/#{version.workflow_id}")
    {_, one} = burst("operations_single", view, [:operations_changed])

    messages =
      List.duplicate(
        [
          :operations_changed,
          :budgets_changed,
          :requests_changed,
          :permissions_changed,
          :workspaces_changed
        ],
        6
      )
      |> List.flatten()

    {_, many} = burst("operations_30_notifications", view, messages)
    assert one.statements == many.statements
  end

  test "notifications arriving during a projection trigger a subsequent current read", %{
    conn: conn
  } do
    f = workflow_fixture()
    id = create_ticket(f)
    {:ok, view, _} = live(login(conn, f.requester), ~p"/o/horizonte/solicitacoes/#{id}")
    _ = :sys.get_state(view.pid)
    marker = :atomics.new(1, [])
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:instantflow, :repo, :query],
        &__MODULE__.block_first_ticket_read/4,
        {view.pid, self(), marker, handler}
      )

    try do
      {_, report} =
        QueryProbe.capture(
          fn ->
            send(view.pid, {:ticket_changed, 1, id})
            assert_receive {:projection_started, ^handler}, 5000
            send(view.pid, {:ticket_changed, 1, id})
            :atomics.put(marker, 1, 2)
            send(view.pid, {:continue_projection, handler})
            render(view)
          end,
          scope: :all
        )

      assert report.groups.history.statements == 2
    after
      :telemetry.detach(handler)

      if :atomics.exchange(marker, 1, 2) == 1,
        do: send(view.pid, {:continue_projection, handler})
    end
  end

  def block_first_ticket_read(_, _, metadata, {view, parent, marker, ref}) do
    if self() == view and metadata.source == "tickets" and
         :atomics.compare_exchange(marker, 1, 0, 1) == :ok do
      send(parent, {:projection_started, ref})

      receive do
        {:continue_projection, ^ref} -> :ok
      after
        5000 -> raise "projection barrier timed out"
      end
    end
  end

  defp burst(label, view, messages) do
    _ = :sys.get_state(view.pid)
    :ok = :sys.suspend(view.pid)
    for message <- messages, do: send(view.pid, message)

    {result, report} =
      QueryProbe.capture(
        fn ->
          :ok = :sys.resume(view.pid)
          render(view)
        end,
        scope: :all
      )

    if path = System.get_env("DB_EFFICIENCY_REPORT"),
      do: File.write!(path, Jason.encode!(Map.put(report, :scenario, label)) <> "\n", [:append])

    {result, report}
  end
end
