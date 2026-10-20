defmodule InstantflowWeb.RequestLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  import Instantflow.WorkflowFixtures
  alias Instantflow.{Repo, WorkflowRuntime}
  alias Instantflow.WorkflowRuntime.Ticket

  test "requester creates, fills and submits a request through the UI", %{conn: conn} do
    f = workflow_fixture()
    conn = login(conn, f.requester)
    {:ok, view, _} = live(conn, ~p"/o/horizonte/solicitacoes")

    view
    |> form("#new-request-form", request: %{workflow_id: f.version.workflow_id})
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "#section-form-request")
    view |> form("#section-form-request", section: values()) |> render_submit()

    view
    |> form("#transition-form", action: %{reason: ""})
    |> render_submit(%{"transition" => "submit"})

    [ticket] = Repo.all(Ticket)
    assert ticket.stage == "review"
    refute has_element?(view, "#section-form-request")
    assert has_element?(view, "#history")
  end

  test "stale form errors preserve drafts and block advancing stale data", %{conn: conn} do
    f = workflow_fixture()
    id = create_ticket(f)
    {:ok, view, _} = live(login(conn, f.requester), ~p"/o/horizonte/solicitacoes/#{id}")

    view
    |> form("#section-form-request",
      section: %{"summary" => "Meu rascunho", "justification" => "Em elaboração"}
    )
    |> render_change()

    save(f.requester, id, values())

    Phoenix.PubSub.broadcast(
      Instantflow.PubSub,
      Instantflow.Delivery.topic(1, id),
      {:ticket_changed, 1, id}
    )

    assert has_element?(view, "#stale-warning")
    assert has_element?(view, "input[value='Meu rascunho']")

    view
    |> form("#section-form-request",
      section: %{"summary" => "Meu rascunho", "justification" => "Em elaboração"}
    )
    |> render_submit()

    assert has_element?(view, "#flash-error", "Seu rascunho foi preservado")
    {:ok, data} = WorkflowRuntime.get(f.requester, id)
    assert hd(data.sections).values == values()
  end

  test "unrelated departments cannot discover or open requests", %{conn: conn} do
    f = workflow_fixture()
    id = create_ticket(f)

    department =
      Repo.insert!(%Instantflow.Identity.Department{organization_id: 1, name: "Outro setor"})

    outsider = staff_fixture("staff")

    Repo.update!(
      Ecto.Changeset.change(Repo.get!(Instantflow.Identity.Membership, outsider.id),
        department_id: department.id
      )
    )

    assert {:error, :not_found} = WorkflowRuntime.get(outsider, id)
    assert WorkflowRuntime.list(outsider) == []

    assert {:error, {:live_redirect, %{to: "/o/horizonte/solicitacoes"}}} =
             live(login(conn, outsider), ~p"/o/horizonte/solicitacoes/#{id}")
  end
end
