defmodule InstantflowWeb.CollaborationLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  import Instantflow.WorkflowFixtures
  import Instantflow.CollaborationFixtures
  alias Instantflow.{Access, Delivery, WorkflowRuntime}

  test "saving one section preserves another draft, while remote conflicts require comparison", %{
    conn: conn
  } do
    f = collaborative_fixture()
    id = create_ticket(f)
    {:ok, first, _} = live(login(conn, f.requester), ~p"/o/horizonte/solicitacoes/#{id}")
    {:ok, second, _} = live(login(conn, f.reviewer), ~p"/o/horizonte/solicitacoes/#{id}")

    first
    |> form("#section-form-notes", section: %{summary: "Meu outro rascunho"})
    |> render_change()

    first |> form("#section-form-request", section: values()) |> render_submit()
    assert has_element?(first, "#section-form-notes input[value='Meu outro rascunho']")
    second |> form("#section-form-notes", section: %{summary: "Versão remota"}) |> render_submit()
    notify(id)
    assert has_element?(first, "#conflict-notes")
    assert has_element?(first, "#case-pending-forms a[href='#conflict-notes']")
    assert has_element?(first, "#section-status-notes", "Conflito")
    assert has_element?(first, "#transition-blocked-explanation a[href='#case-action-summary']")
    assert has_element?(first, "#section-form-notes input[value='Meu outro rascunho']")
    first |> element("#conflict-notes button", "Revisar alterações") |> render_click()
    assert has_element?(first, "#comparison-notes dd", "Versão remota")
    first |> element("#comparison-notes button") |> render_click()
    refute has_element?(first, "#conflict-notes")

    first
    |> form("#section-form-notes", section: %{summary: "Meu outro rascunho"})
    |> render_submit()

    {:ok, data} = WorkflowRuntime.get(f.requester, id)

    assert Enum.find(data.sections, &(&1.key == "notes")).values["summary"] ==
             "Meu outro rascunho"

    assert Enum.find(data.sections, &(&1.key == "request")).values == values()
    refute has_element?(first, "#case-pending-forms")
    assert has_element?(first, "#section-status-notes", "Sem alterações locais")
  end

  test "revoking a section grant clears its protected draft without losing other authorized drafts",
       %{conn: conn} do
    f = collaborative_fixture()
    id = create_ticket(f)
    {:ok, {_, grant}} = Access.grant(f.admin, f.reviewer.id, f.reviewer.department_id, "finance")
    {:ok, view, _} = live(login(conn, f.reviewer), ~p"/o/horizonte/solicitacoes/#{id}")

    view
    |> form("#section-form-finance", section: %{summary: "Segredo em elaboração"})
    |> render_change()

    view
    |> form("#section-form-notes", section: %{summary: "Notas preservadas"})
    |> render_change()

    {:ok, _} = Access.revoke(f.admin, grant.id)
    refute has_element?(view, "#section-form-finance")
    refute has_element?(view, "input[value='Segredo em elaboração']")
    assert has_element?(view, "#section-form-notes input[value='Notas preservadas']")
  end

  test "duplicate, out-of-order and foreign record invalidations converge and refresh keeps drafts",
       %{conn: conn} do
    f = collaborative_fixture()
    id = create_ticket(f)
    {:ok, view, _} = live(login(conn, f.requester), ~p"/o/horizonte/solicitacoes/#{id}")
    view |> form("#section-form-notes", section: %{summary: "Em memória"}) |> render_change()
    other_id = create_ticket(f)
    send(view.pid, {:ticket_changed, 1, other_id})
    {:ok, data} = WorkflowRuntime.get(f.reviewer, id)
    {:ok, _} = WorkflowRuntime.command(f.reviewer, section_command(data, "request", values()))
    notify(id)
    notify(id)
    view |> element("#refresh-request") |> render_click()
    assert has_element?(view, "#section-form-notes input[value='Em memória']")
    assert has_element?(view, "#section-form-request input[value='Material para atividade']")
    assert has_element?(view, "#transition-submit[disabled]")
    assert has_element?(view, "#review-request")
  end

  test "dashboard filters scoped counts and refreshes from its local subscription", %{conn: conn} do
    f = collaborative_fixture()
    id = create_ticket(f)
    {:ok, view, _} = live(login(conn, f.requester), ~p"/o/horizonte/solicitacoes")
    assert has_element?(view, "#requests-count", "1 disponíveis")
    create_ticket(f)

    Phoenix.PubSub.broadcast(
      Instantflow.PubSub,
      WorkflowRuntime.list_topic(f.requester),
      :requests_changed
    )

    assert has_element?(view, "#requests-count", "2 disponíveis")

    view
    |> form("#request-filters", filter: %{query: to_string(id), stage: "draft"})
    |> render_submit()

    assert has_element?(view, "#filtered-count", "1 resultado(s)")
    assert has_element?(view, "#tickets-#{id}")
  end

  test "recovering a disconnected draft preserves observed revisions and never submits it", %{
    conn: conn
  } do
    f = collaborative_fixture()
    id = create_ticket(f)
    {:ok, data} = WorkflowRuntime.get(f.requester, id)

    observed = %{
      "revision" => "1",
      "stage_revision" => to_string(data.ticket.stage_revision),
      "key" => "recovered-command"
    }

    {:ok, _} =
      WorkflowRuntime.command(
        f.reviewer,
        section_command(data, "notes", %{"summary" => "Salvo enquanto desconectado"})
      )

    {:ok, view, _} = live(login(conn, f.requester), ~p"/o/horizonte/solicitacoes/#{id}")

    render_change(view, "recover_draft", %{
      "key" => "notes",
      "section" => %{"summary" => "Rascunho desconectado"},
      "observed" => observed
    })

    assert has_element?(view, "#section-form-notes input[value='Rascunho desconectado']")
    assert has_element?(view, "#conflict-notes")
    {:ok, final} = WorkflowRuntime.get(f.requester, id)

    assert Enum.find(final.sections, &(&1.key == "notes")).values["summary"] ==
             "Salvo enquanto desconectado"
  end

  defp notify(id),
    do:
      Phoenix.PubSub.broadcast(
        Instantflow.PubSub,
        Delivery.topic(1, id),
        {:ticket_changed, 1, id}
      )

  test "a lost save acknowledgement reuses its recovered key despite unused-field metadata", %{
    conn: conn
  } do
    f = collaborative_fixture()
    id = create_ticket(f)
    {:ok, data} = WorkflowRuntime.get(f.requester, id)
    command = section_command(data, "notes", values(), "lost-ack-key")
    {:ok, result} = WorkflowRuntime.command(f.requester, command)
    {:ok, view, _} = live(login(conn, f.requester), ~p"/o/horizonte/solicitacoes/#{id}")

    render_change(view, "recover_draft", %{
      "key" => "notes",
      "section" => Map.put(values(), "_unused_justification", ""),
      "observed" => %{"revision" => "1", "stage_revision" => "1", "key" => "lost-ack-key"}
    })

    view |> form("#section-form-notes", section: values()) |> render_submit()
    {:ok, final} = WorkflowRuntime.get(f.requester, id)
    assert final.ticket.revision == result["revision"]
    assert Enum.count(final.events, &(&1.operation == "save:notes")) == 1
    refute has_element?(view, "#conflict-notes")
    refute has_element?(view, "#flash-error")
  end
end
