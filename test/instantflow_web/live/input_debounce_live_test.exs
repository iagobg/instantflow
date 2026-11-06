defmodule InstantflowWeb.InputDebounceLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  import Instantflow.WorkflowFixtures
  alias Instantflow.WorkflowRuntime

  test "dirty forms debounce text changes and save the full submitted values", %{conn: conn} do
    f = workflow_fixture()
    id = create_ticket(f)
    {:ok, view, _} = live(login(conn, f.requester), ~p"/o/horizonte/solicitacoes/#{id}")
    refute has_element?(view, "#section-request-summary[phx-debounce]")

    view |> form("#section-form-request", section: values()) |> render_change()
    assert has_element?(view, "#section-request-summary[phx-debounce='250']")
    assert has_element?(view, "#section-request-justification[phx-debounce='250']")
    assert has_element?(view, "#transition-submit[disabled]")

    final = Map.put(values(), "summary", "Final text before the debounce fires")
    view |> form("#section-form-request", section: final) |> render_submit()
    assert {:ok, data} = WorkflowRuntime.get(f.requester, id)
    assert hd(data.sections).values == final
    refute has_element?(view, "#section-request-summary[phx-debounce]")
  end

  test "save also accepts values before the first draft change has arrived", %{conn: conn} do
    f = workflow_fixture()
    id = create_ticket(f)
    {:ok, view, _} = live(login(conn, f.requester), ~p"/o/horizonte/solicitacoes/#{id}")
    view |> form("#section-form-request", section: values()) |> render_submit()
    assert {:ok, data} = WorkflowRuntime.get(f.requester, id)
    assert hd(data.sections).values == values()
  end

  test "transition uses its submitted reason without a preceding reason change", %{conn: conn} do
    f = workflow_fixture()
    id = create_ticket(f)
    {:ok, view, _} = live(login(conn, f.requester), ~p"/o/horizonte/solicitacoes/#{id}")
    assert has_element?(view, "#transition-form textarea[phx-debounce='250']")

    view
    |> form("#transition-form", action: %{reason: "Current required reason"})
    |> render_submit(%{"transition" => "cancel_draft"})

    assert {:ok, data} = WorkflowRuntime.get(f.requester, id)
    assert data.ticket.stage == "cancelled"
    assert Enum.any?(data.events, &(&1.reason == "Current required reason"))
    refute has_element?(view, "#transition-cancel_draft")
  end
end
