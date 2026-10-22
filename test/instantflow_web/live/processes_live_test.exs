defmodule InstantflowWeb.ProcessesLiveTest do
  use InstantflowWeb.ConnCase
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  import Instantflow.OperationsFixtures
  alias Instantflow.WorkflowCatalog.Templates

  test "empty organizations have no school or operational module navigation", %{conn: conn} do
    actor = staff_fixture()
    {:ok, view, _} = live(login(conn, actor), ~p"/o/horizonte/processos")
    assert has_element?(view, "#processes-empty")
    refute has_element?(view, "#enrollment-link")
    refute has_element?(view, "#incidents-link")
    refute has_element?(view, "#budgets-link")
    refute has_element?(view, "#records-link")
    refute has_element?(view, "a[href='/o/horizonte/operacao']")

    for route <- [
          "/o/horizonte/matriculas",
          "/o/horizonte/ocorrencias",
          "/o/horizonte/orcamentos"
        ] do
      assert {:error, {:redirect, %{to: "/o/horizonte/processos"}}} =
               live(login(conn, actor), route)
    end
  end

  test "restaurant gets only configured processes and independent workspace links", %{conn: conn} do
    actor = staff_fixture()
    a = install_operations(actor, "restaurant", "Pedidos do restaurante")
    b = install_operations(actor, "counter", "Vendas do balcão")
    {:ok, view, _} = live(login(conn, actor), ~p"/o/horizonte/processos")

    assert has_element?(
             view,
             "#open-process-#{a.workflow_id}[href='/o/horizonte/processos/#{a.workflow_id}']"
           )

    assert has_element?(view, "#open-process-#{b.workflow_id}")
    assert has_element?(view, "#process-link-#{a.workflow_id}", "Pedidos do restaurante")
    refute has_element?(view, "#enrollment-link")
    refute has_element?(view, "#records-link")

    assert {:error, {:live_redirect, %{to: "/o/horizonte/processos"}}} =
             live(login(conn, actor), ~p"/o/horizonte/operacao")
  end

  test "process creation exposes reusable starters and workspace names in the editor", %{
    conn: conn
  } do
    actor = staff_fixture()
    {:ok, view, _} = live(login(conn, actor), ~p"/o/horizonte/modelos")
    assert has_element?(view, "#workflow_type option[value='item_service']")
    assert has_element?(view, "#workflow_type option[value='enrollment']")
    assert {:ok, draft} = Templates.new(actor, "rental", "Locações", "item_service")
    {:ok, editor, _} = live(login(conn, actor), ~p"/o/horizonte/modelos/#{draft.id}")

    editor
    |> form("#workspace-labels-form",
      workspace: %{
        resource: "Sala",
        resources: "Salas",
        catalog: "Serviços",
        actor: "Atendente",
        destination: "Setor"
      }
    )
    |> render_submit()

    assert has_element?(editor, "#workspace_catalog[value='Serviços']")
    assert {:ok, saved} = Templates.get(actor, draft.id)
    assert saved.definition["interface"]["labels"]["resource"] == "Sala"
  end

  test "copied school examples use the same generated pages and record renderer", %{conn: conn} do
    f = Instantflow.EnrollmentFixtures.enrollment_fixture()

    definition =
      f.version.definition
      |> Map.put("template_key", "independent_intake")
      |> Map.put("name", "Admissão complementar")

    {:ok, version} = Instantflow.WorkflowCatalog.publish(f.admin, definition, f.version.bindings)

    {:ok, record} =
      Instantflow.WorkflowRuntime.command(f.admin, %{
        "operation" => "create",
        "workflow_id" => version.workflow_id,
        "key" => Ecto.UUID.generate()
      })

    {:ok, view, _} = live(login(conn, f.admin), ~p"/o/horizonte/processos/#{version.workflow_id}")
    assert has_element?(view, "h1", "Admissão complementar")
    assert has_element?(view, "#open-process-record-#{record["ticket_id"]}")
    refute has_element?(view, "#open-process-record-#{f.enrollment.ticket_id}")

    {:ok, record_view, _} =
      live(
        login(conn, f.admin),
        ~p"/o/horizonte/processos/#{version.workflow_id}/registros/#{record["ticket_id"]}"
      )

    assert has_element?(record_view, "#main-content")
  end

  test "editor-defined pages generate URLs and compose only their declared blocks", %{conn: conn} do
    actor = staff_fixture()
    {:ok, draft} = Templates.new(actor, "service", "Atendimentos", "item_service")

    config =
      draft.definition["interface"]
      |> Map.put("pages", [
        %{"key" => "setup", "label" => "Preparar", "blocks" => ["catalog", "resources"]},
        %{"key" => "reports", "label" => "Resultados", "blocks" => ["daily_summary"]}
      ])

    {:ok, saved} =
      Templates.save(
        actor,
        draft.id,
        draft.revision,
        Map.put(draft.definition, "interface", config),
        draft.bindings
      )

    {:ok, version} = Templates.publish(actor, saved.id, saved.revision)

    {:ok, setup, _} =
      live(login(conn, actor), ~p"/o/horizonte/processos/#{version.workflow_id}/p/setup")

    assert has_element?(setup, "#product-form")
    assert has_element?(setup, "#open-visit-form")
    refute has_element?(setup, "#daily-report")

    {:ok, report, _} =
      live(login(conn, actor), ~p"/o/horizonte/processos/#{version.workflow_id}/p/reports")

    assert has_element?(report, "#daily-report")
    refute has_element?(report, "#product-form")

    assert has_element?(
             report,
             "#process-page-setup[href='/o/horizonte/processos/#{version.workflow_id}/p/setup']"
           )
  end

  test "a reviewer can open a generated form process without administrator privileges", %{
    conn: conn
  } do
    f = Instantflow.WorkflowFixtures.workflow_fixture()

    {:ok, view, _} =
      live(login(conn, f.reviewer), ~p"/o/horizonte/processos/#{f.version.workflow_id}")

    assert has_element?(view, "#process-records-block")
    refute has_element?(view, "#product-form")
  end

  test "switching generated pages preserves the same visit's unsent batch", %{conn: conn} do
    f = operations_fixture()
    workflow_id = Instantflow.Operations.default_workflow(f.actor)

    definition =
      Application.app_dir(:instantflow, "priv/workflows/resource_service.json")
      |> File.read!()
      |> Jason.decode!()

    definition =
      update_in(
        definition,
        ["interface", "pages"],
        &(&1 ++ [%{"key" => "reports", "label" => "Resultados", "blocks" => ["daily_summary"]}])
      )

    {:ok, _} =
      Instantflow.WorkflowCatalog.publish(
        f.actor,
        definition,
        %{
          "roles" => %{"operator" => ["admin"]},
          "departments" => %{"service_department" => f.actor.department_id}
        },
        1
      )

    visit = open_visit(f)

    {:ok, view, _} =
      live(
        login(conn, f.actor),
        ~p"/o/horizonte/processos/#{workflow_id}/p/overview/atendimentos/#{visit}"
      )

    view |> element("#quick_products-#{f.soup}") |> render_click()
    assert has_element?(view, "#cart-total", "R$ 25,50")
    view |> element("#process-page-reports") |> render_click()
    refute has_element?(view, "#cart-total")
    view |> element("#process-page-overview") |> render_click()
    assert has_element?(view, "#cart-total", "R$ 25,50")
    assert Instantflow.Operations.visit(f.actor, visit).total == 0
  end

  test "the page composition form saves selections and reordering preserves block access", %{
    conn: conn
  } do
    actor = staff_fixture()
    {:ok, draft} = Templates.new(actor, "service", "Atendimentos", "item_service")
    {:ok, editor, _} = live(login(conn, actor), ~p"/o/horizonte/modelos/#{draft.id}")
    assert has_element?(editor, "#interface-access-view option[value='operator'][selected]")

    editor
    |> form("#interface-page-form",
      interface_page: %{
        key: "overview",
        label: "Preparar",
        blocks: ["catalog", "resources"],
        close_transition: "settle",
        access_view: ["operator"],
        access_configure: ["operator"],
        access_operate: ["operator"]
      }
    )
    |> render_submit()

    {:ok, saved} = Templates.get(actor, draft.id)
    assert hd(saved.definition["interface"]["pages"])["blocks"] == ["catalog", "resources"]
    editor |> element("#move-block-down-0") |> render_click()
    {:ok, reordered} = Templates.get(actor, draft.id)
    assert hd(reordered.definition["interface"]["pages"])["blocks"] == ["resources", "catalog"]
    assert reordered.definition["interface"]["access"]["view"] == ["operator"]
  end

  test "valid processes without configured views render and can start records", %{conn: conn} do
    f = Instantflow.WorkflowFixtures.workflow_fixture()
    definition = f.definition |> Map.put("template_key", "no_views") |> Map.put("views", [])
    assert {:ok, version} = Instantflow.WorkflowCatalog.publish(f.admin, definition, f.bindings)

    assert {:ok, view, _} =
             live(login(conn, f.admin), ~p"/o/horizonte/processos/#{version.workflow_id}")

    assert has_element?(view, "#process-record-views-empty")
    refute has_element?(view, "#process-record-filters")
    view |> element("#create-process-record") |> render_click()
    {path, _flash} = assert_redirect(view)
    assert path =~ ~r"/o/horizonte/processos/#{version.workflow_id}/registros/[0-9]+"
  end

  test "operational pages do not require an unrelated record-view definition", %{conn: conn} do
    actor = staff_fixture()

    definition =
      Templates.starter("counter_without_views", "Balcão", "item_service") |> Map.put("views", [])

    assert {:ok, version} =
             Instantflow.WorkflowCatalog.publish(actor, definition, %{
               "roles" => %{"operator" => ["admin"]},
               "departments" => %{"service_department" => actor.department_id}
             })

    assert {:ok, view, _} =
             live(login(conn, actor), ~p"/o/horizonte/processos/#{version.workflow_id}")

    assert has_element?(view, "#open-visit-form")
    refute has_element?(view, "#process-records-block")
  end
end
