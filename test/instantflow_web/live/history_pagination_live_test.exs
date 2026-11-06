defmodule InstantflowWeb.HistoryPaginationLiveTest do
  use InstantflowWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  import Instantflow.WorkflowFixtures
  import Instantflow.CollaborationFixtures
  alias Instantflow.{Access, HistoryFixtures, Repo}

  test "history and delivery paging preserves drafts and reconciles the selected page", %{
    conn: conn
  } do
    f = collaborative_fixture()
    id = create_ticket(f)
    events = HistoryFixtures.append(f.requester, id, 2..103)
    messages = HistoryFixtures.deliveries(events)

    {{:ok, view, _}, report} =
      Instantflow.Diagnostics.QueryProbe.capture(
        fn ->
          live(login(conn, f.requester), ~p"/o/horizonte/solicitacoes/#{id}")
        end,
        scope: :all
      )

    if path = System.get_env("DB_EFFICIENCY_REPORT"),
      do:
        File.write!(
          path,
          Jason.encode!(Map.put(report, :scenario, "history_page_mount_103")) <> "\n",
          [:append]
        )

    assert row_count(view, "#history > article") == 50
    assert row_count(view, "#deliveries > .delivery-row") == 50
    assert :sys.get_state(view.pid).socket.assigns.data.events == []
    assert :sys.get_state(view.pid).socket.assigns.data.deliveries == []

    {_, timestamp_queries} =
      Instantflow.TimestampProbe.capture(fn -> render_hook(view, "reconcile", %{}) end)

    assert timestamp_queries == 1
    assert has_element?(view, "#history article small", "São Paulo")
    Repo.update!(Ecto.Changeset.change(f.requester.organization, timezone: "Asia/Tokyo"))
    render_hook(view, "reconcile", %{})
    assert has_element?(view, "#history article small", "Asia/Tokyo")
    refute has_element?(view, "#history article small", "São Paulo")

    {_, heartbeat_queries} =
      Instantflow.TimestampProbe.capture(fn -> render_hook(view, "heartbeat", %{}) end)

    assert heartbeat_queries == 0
    view |> form("#section-form-notes", section: %{summary: "Keep this draft"}) |> render_change()
    view |> element("#older-history") |> render_click()
    assert row_count(view, "#history > article") == 50
    assert has_element?(view, "#events-#{Enum.at(events, 51).id}")
    send(view.pid, :reconcile)
    assert has_element?(view, "#events-#{Enum.at(events, 51).id}")
    view |> element("#older-history") |> render_click()
    assert row_count(view, "#history > article") == 3
    refute has_element?(view, "#older-history")
    view |> element("#recent-history") |> render_click()
    assert row_count(view, "#history > article") == 50

    view |> element("#older-deliveries") |> render_click()
    assert row_count(view, "#deliveries > .delivery-row") == 50
    view |> element("#older-deliveries") |> render_click()
    assert row_count(view, "#deliveries > .delivery-row") == 2
    assert has_element?(view, "#deliveries-#{hd(messages).id}")
    view |> element("#recent-deliveries") |> render_click()
    assert row_count(view, "#deliveries > .delivery-row") == 50
    assert has_element?(view, "#section-form-notes input[value='Keep this draft']")
  end

  test "reconciliation removes revoked history even without a permission broadcast", %{conn: conn} do
    f = collaborative_fixture()
    id = create_ticket(f)
    {:ok, {_, grant}} = Access.grant(f.admin, f.reviewer.id, f.reviewer.department_id, "finance")
    [private | _] = HistoryFixtures.append(f.requester, id, 2..103, "save:finance")
    {:ok, view, _} = live(login(conn, f.reviewer), ~p"/o/horizonte/solicitacoes/#{id}")
    view |> element("#older-history") |> render_click()
    view |> element("#older-history") |> render_click()
    assert has_element?(view, "#events-#{private.id}")
    Repo.delete!(grant)
    render_hook(view, "reconcile", %{})
    refute has_element?(view, "#events-#{private.id}")
    assert row_count(view, "#history > article") == 1
  end

  defp row_count(view, selector),
    do: view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()
end
