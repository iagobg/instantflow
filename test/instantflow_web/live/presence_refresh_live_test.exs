defmodule InstantflowWeb.PresenceRefreshLiveTest do
  use InstantflowWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  import Instantflow.CollaborationFixtures
  import Instantflow.WorkflowFixtures
  alias Instantflow.{Access, Repo, WorkflowRuntime}
  alias Instantflow.Diagnostics.QueryProbe

  test "unchanged heartbeat avoids history; missed record updates still reconcile drafts", %{
    conn: conn
  } do
    f = collaborative_fixture()
    id = create_ticket(f)
    {:ok, view, _} = live(login(conn, f.requester), ~p"/o/horizonte/solicitacoes/#{id}")
    {_, idle} = QueryProbe.capture(fn -> render_hook(view, "heartbeat", %{}) end, scope: :all)
    assert idle.groups.history.statements == 0
    assert idle.groups.documents.statements == 0
    assert has_element?(view, "#section-form-request")

    view |> form("#section-form-notes", section: %{summary: "Keep draft"}) |> render_change()
    {:ok, current} = WorkflowRuntime.get(f.reviewer, id)

    assert {:ok, _} =
             WorkflowRuntime.command(f.reviewer, section_command(current, "request", values()))

    # Workers are disabled: no delivery is needed to discover the new revision.
    render_hook(view, "heartbeat", %{})
    assert has_element?(view, "#section-form-notes input[value='Keep draft']")
    assert has_element?(view, "#section-form-request input[value='Material para atividade']")
    assert has_element?(view, "#review-request")
  end

  test "heartbeat clears a revoked draft even when its permission broadcast is lost", %{
    conn: conn
  } do
    f = collaborative_fixture()
    id = create_ticket(f)
    {:ok, {_, grant}} = Access.grant(f.admin, f.reviewer.id, f.reviewer.department_id, "finance")
    {:ok, view, _} = live(login(conn, f.reviewer), ~p"/o/horizonte/solicitacoes/#{id}")
    view |> form("#section-form-finance", section: %{summary: "Private draft"}) |> render_change()

    view
    |> form("#section-form-notes", section: %{summary: "Keep public draft"})
    |> render_change()

    Repo.delete!(grant)
    render_hook(view, "heartbeat", %{})
    refute has_element?(view, "#section-form-finance")
    assert has_element?(view, "#section-form-notes input[value='Keep public draft']")
  end

  test "a draft event cannot retain a section whose edit grant disappeared", %{conn: conn} do
    f = collaborative_fixture()
    id = create_ticket(f)
    {:ok, {_, grant}} = Access.grant(f.admin, f.reviewer.id, f.reviewer.department_id, "finance")
    {:ok, view, _} = live(login(conn, f.reviewer), ~p"/o/horizonte/solicitacoes/#{id}")
    Repo.delete!(grant)
    view |> form("#section-form-finance", section: %{summary: "Stale edit"}) |> render_change()
    refute has_element?(view, "#section-form-finance")
    refute Map.has_key?(:sys.get_state(view.pid).socket.assigns.editors, "finance")
  end
end
