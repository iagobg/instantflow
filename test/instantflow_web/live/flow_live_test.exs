defmodule InstantflowWeb.FlowLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  import Instantflow.WorkflowFixtures
  alias Instantflow.{Access, Delivery, Repo, WorkflowCatalog}
  alias Instantflow.WorkflowCatalog.Templates

  test "workspace and record link to published and pinned flows; viewing does not require editing",
       %{conn: conn} do
    f = workflow_fixture()
    id = create_ticket(f)

    {:ok, process, _} =
      live(login(conn, f.requester), ~p"/o/horizonte/processos/#{f.version.workflow_id}")

    assert has_element?(
             process,
             "#process-flow-link[href^='/o/horizonte/processos/#{f.version.workflow_id}/fluxo']"
           )

    {:ok, flow, _} =
      live(login(conn, f.requester), ~p"/o/horizonte/processos/#{f.version.workflow_id}/fluxo")

    assert has_element?(flow, "#flow-version[data-version-id='#{f.version.id}']", "Versão 1")
    assert has_element?(flow, "#workflow-graph-viewport[tabindex='0']")
    assert has_element?(flow, "#flow-current-context")
    assert has_element?(flow, "#flow-back-process")
    refute has_element?(flow, "#flow-builder-link")
    refute has_element?(flow, "#publish-template")
    assert has_element?(flow, "#flow-stages [data-transition='request_correction']")
    form(flow, "#graph-focus-form", graph: %{stage: "review"}) |> render_change()
    assert has_element?(flow, "#graph-nodes [data-stage='review'].focused")
    assert has_element?(flow, "#flow-stages [data-stage='draft']")

    {:ok, record, _} =
      live(
        login(conn, f.requester),
        ~p"/o/horizonte/processos/#{f.version.workflow_id}/registros/#{id}"
      )

    assert has_element?(
             record,
             "#record-flow-link[href='/o/horizonte/processos/#{f.version.workflow_id}/registros/#{id}/fluxo']"
           )

    {:ok, admin_flow, _} =
      live(login(conn, f.admin), ~p"/o/horizonte/processos/#{f.version.workflow_id}/fluxo")

    assert has_element?(admin_flow, "#flow-builder-link[href='/o/horizonte/modelos']")
  end

  test "case flow stays pinned and updates its current stage after another actor's commands", %{
    conn: conn
  } do
    f = workflow_fixture()
    id = create_ticket(f)
    assert {:ok, _} = save(f.requester, id, values())

    {:ok, flow, _} =
      live(
        login(conn, f.requester),
        ~p"/o/horizonte/processos/#{f.version.workflow_id}/registros/#{id}/fluxo"
      )

    assert has_element?(flow, "#graph-nodes [data-stage='draft'][aria-current='step']")
    assert has_element?(flow, "#flow-stages [data-stage='draft'][aria-current='step']")

    flow |> form("#graph-focus-form", graph: %{stage: "review"}) |> render_change()
    assert has_element?(flow, "#graph-current-status", "Rascunho")
    assert has_element?(flow, "#graph-inspection-status", "Em análise")
    assert has_element?(flow, "#graph-inspection-connections", "Solicitar correção")
    assert has_element?(flow, "#graph-nodes [data-stage='draft'][aria-current='step']")
    flow |> element("#graph-overview") |> render_click()
    refute has_element?(flow, "#graph-nodes .focused")
    assert has_element?(flow, "#graph-current-status", "Rascunho")
    flow |> element("#graph-current") |> render_click()
    assert has_element?(flow, "#graph-nodes [data-stage='draft'].focused")
    assert {:ok, _} = transition(f.requester, id, "submit")
    Delivery.drain()
    assert has_element?(flow, "#graph-nodes [data-stage='review'][aria-current='step']")
    refute has_element?(flow, "#graph-nodes [data-stage='draft'][aria-current='step']")
    assert {:ok, _} = transition(f.reviewer, id, "request_correction", "Revisão fictícia")
    Delivery.drain()
    assert has_element?(flow, "#flow-stages [data-stage='correction'][aria-current='step']")

    {:ok, overview, _} =
      live(login(conn, f.requester), ~p"/o/horizonte/processos/#{f.version.workflow_id}/fluxo")

    form(overview, "#graph-focus-form", graph: %{stage: "review"}) |> render_change()

    newer = put_in(f.definition, ["stages", Elixir.Access.at(0), "label"], "Recepção nova")
    assert {:ok, version} = WorkflowCatalog.publish(f.admin, newer, f.bindings, 1)
    assert has_element?(flow, "#flow-version[data-version-id='#{f.version.id}']", "Versão 1")
    assert has_element?(flow, "#flow-pin-context")

    assert has_element?(overview, "#flow-version[data-version-id='#{version.id}']", "Versão 2")
    assert has_element?(overview, "#graph-nodes [data-stage='review'].focused")
    assert has_element?(overview, "#flow-stages [data-stage='draft']", "Recepção nova")
  end

  test "revoking a viewing grant clears all diagram and stage data in an open flow", %{conn: conn} do
    f = Instantflow.FinanceFixtures.finance_fixture()

    {:ok, flow, _} =
      live(login(conn, f.requester), ~p"/o/horizonte/processos/#{f.version.workflow_id}/fluxo")

    assert has_element?(flow, "#workflow-graph")
    grant = Repo.get_by!(Access.Grant, membership_id: f.requester.id, role: "teacher")
    assert {:ok, _} = Access.revoke(f.admin, grant.id)
    send(flow.pid, :reconcile)
    assert has_element?(flow, "#flow-unavailable")
    refute has_element?(flow, "#workflow-graph")
    refute has_element?(flow, "#flow-stages")
    refute has_element?(flow, "#flow-version")
  end

  test "bad ids and mismatched record routes show a generic unavailable state", %{conn: conn} do
    f = workflow_fixture()
    id = create_ticket(f)

    for path <- [
          "/o/horizonte/processos/invalid/fluxo",
          "/o/horizonte/processos/#{f.version.workflow_id}/registros/invalid/fluxo",
          "/o/horizonte/processos/#{f.version.workflow_id + 1000}/registros/#{id}/fluxo"
        ] do
      {:ok, flow, _} = live(login(conn, f.requester), path)
      assert has_element?(flow, "#flow-unavailable")
      refute has_element?(flow, "#flow-version")
    end
  end

  test "long stage labels remain available in the readable list and editor graph still renders",
       %{conn: conn} do
    f = workflow_fixture()
    label = String.duplicate("Etapa de conferência documental ", 3) |> String.trim()
    definition = put_in(f.definition, ["stages", Elixir.Access.at(0), "label"], label)
    {:ok, version} = WorkflowCatalog.publish(f.admin, definition, f.bindings, 1)

    {:ok, flow, _} =
      live(login(conn, f.requester), ~p"/o/horizonte/processos/#{version.workflow_id}/fluxo")

    assert has_element?(flow, "#flow-stages [data-stage='draft'] h3", label)
    assert has_element?(flow, "#graph-nodes [data-stage='draft'] title", label)
    {:ok, draft} = Templates.clone(f.admin, version.id)
    {:ok, editor, _} = live(login(conn, f.admin), ~p"/o/horizonte/modelos/#{draft.id}")
    assert has_element?(editor, "#workflow-graph")
    form(editor, "#graph-focus-form", graph: %{stage: "review"}) |> render_change()
    assert has_element?(editor, "#graph-nodes [data-stage='review'].focused")
  end
end
