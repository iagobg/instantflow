defmodule InstantflowWeb.OperationsPaginationLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  import Instantflow.OperationsFixtures
  alias Instantflow.Operations

  test "catalog/resource search reaches later pages, keeps the cart and prints later captured batches" do
    f = operations_fixture()
    version = Operations.workspace(f.actor, Operations.today(f.actor)).version

    targets =
      for n <- 1..30 do
        {:ok, _} =
          operation(f.actor, "save_product", %{
            "workflow_id" => version.workflow_id,
            "name" => "Produto #{n}",
            "category" => "Geral",
            "price" => 100,
            "destination" => "Cozinha"
          })

        {:ok, resource} =
          operation(f.actor, "add_resource", %{
            "workflow_id" => version.workflow_id,
            "name" => "Posto #{n}"
          })

        resource["id"]
      end

    {:ok, water} =
      operation(f.actor, "save_product", %{
        "workflow_id" => version.workflow_id,
        "name" => "Água mineral",
        "category" => "Geral",
        "price" => 400,
        "destination" => "Cozinha"
      })

    {:ok, view, _} =
      live(login(build_conn(), f.actor), "/o/horizonte/processos/#{version.workflow_id}")

    assert has_element?(view, "#resource-browser-count", "31 resultado(s)")
    view |> element("#resource-browser-next") |> render_click()
    view |> form("#resource-browser-filters", browse: %{query: "Posto 30"}) |> render_submit()
    assert has_element?(view, "#resource-browser-count", "1 resultado(s)")

    view
    |> form("#open-visit-form",
      visit: %{
        resource_id: List.last(targets),
        responsible_actor: "Operador paginado",
        business_date: Date.to_iso8601(Operations.today(f.actor))
      }
    )
    |> render_submit()

    assert has_element?(view, "#active-visit", "Posto 30")
    view |> form("#catalog-items-filters", browse: %{query: "agua mineral"}) |> render_submit()
    assert has_element?(view, "#catalog-items-count", "1 resultado(s)")
    view |> element("#quick_products-#{water["id"]}") |> render_click()
    view |> form("#catalog-items-filters", browse: %{query: "Produto 1"}) |> render_submit()
    assert has_element?(view, "#cart-total", "R$ 4,00")

    view
    |> form("#submit-batch-form", batch: %{responsible_actor: "Operador paginado"})
    |> render_submit()

    data =
      Operations.workspace(f.actor, Operations.today(f.actor), version.workflow_id, nil, %{
        "resources_query" => "Posto 30"
      })

    session = hd(data.sessions)

    for _ <- 1..11 do
      {:ok, _} =
        operation(f.actor, "submit_batch", %{
          "workflow_id" => version.workflow_id,
          "session_id" => session.id,
          "lines" => [item(f.actor, f.soup)]
        })
    end

    render_click(view, "reconcile", %{})
    assert has_element?(view, "#batch-browser-count", "12 resultado(s)")
    view |> element("#batch-browser-next") |> render_click()
    last = Operations.visit(f.actor, session.id, version.workflow_id, %{"batches_page" => "2"})
    assert length(last.batches) == 2

    for batch <- last.batches do
      assert has_element?(view, "#print-batch-#{batch.id}")
    end

    view |> element("#print-batch-#{List.last(last.batches).id}") |> render_click()
    assert_push_event(view, "operations:print", %{})
    assert has_element?(view, "#operation-print", "Sopa")
    assert last.total == 28450
  end
end
