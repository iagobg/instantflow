defmodule InstantflowWeb.OperationsLiveTest do
  use InstantflowWeb.ConnCase
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  import Instantflow.OperationsFixtures
  alias Instantflow.Operations

  test "administrator sets up the menu, selects products, prints split tickets and settles a visit",
       %{conn: conn} do
    actor = staff_fixture()
    install_operations(actor)

    {:ok, view, _} =
      live(login(conn, actor), ~p"/o/horizonte/processos/#{Operations.default_workflow(actor)}")

    assert has_element?(view, "#product-form")

    view
    |> form("#product-form",
      product: %{
        name: "Sopa",
        category: "Entradas",
        price: "25,50",
        destination: "Cozinha",
        active: "true"
      }
    )
    |> render_submit()

    view
    |> form("#product-form",
      product: %{
        name: "Asado",
        category: "Carnes",
        price: "80,00",
        destination: "Parrilla",
        active: "true"
      }
    )
    |> render_submit()

    view |> form("#resource-form", resource: %{name: "Mesa 08"}) |> render_submit()
    data = Operations.workspace(actor, Operations.today(actor))
    [resource] = data.resources

    view
    |> form("#open-visit-form",
      visit: %{
        resource_id: resource.id,
        responsible_actor: "Carlos",
        business_date: Date.to_iso8601(Operations.today(actor))
      }
    )
    |> render_submit()

    assert has_element?(view, "#active-visit")
    render_click(view, "heartbeat", %{})
    render_click(view, "reconcile", %{})
    assert has_element?(view, "#active-visit")

    for product <- data.products do
      view
      |> form("#add-item-form", item: %{quantity: "2", notes: "Sem sal"})
      |> render_submit(%{
        "item" => %{
          "product_id" => to_string(product.id),
          "product_revision" => to_string(product.revision)
        }
      })
    end

    assert has_element?(view, "#cart-total", "R$ 211,00")
    view |> form("#submit-batch-form", batch: %{responsible_actor: "Ana"}) |> render_submit()
    session = hd(Operations.workspace(actor, Operations.today(actor)).sessions)
    batches = Operations.visit(actor, session.id).batches
    assert length(batches) == 2

    for batch <- batches do
      view |> element("#print-batch-#{batch.id}") |> render_click()
      assert_push_event(view, "operations:print", %{})
      assert has_element?(view, "#operation-print", batch.destination)
      assert has_element?(view, "#operation-print", "Ana")
      assert has_element?(view, "#operation-print", "Mesa 08")
      view |> element("#print-batch-#{batch.id}") |> render_click()
      assert has_element?(view, "#operation-print", "REIMPRESSÃO")
      view |> element("#handoff-#{batch.id}") |> render_click()
    end

    view |> form("#checkout-form", checkout: %{payment_method: "pix"}) |> render_submit()
    assert has_element?(view, "#visit-settled")
    assert has_element?(view, "#day-sales", "R$ 211,00")
    refute has_element?(view, "#checkout-form")
    view |> element("#close-day") |> render_click()
    assert has_element?(view, "#day-closed")
  end

  test "non-admin cannot see the workspace or mutate it with a forged event", %{conn: conn} do
    actor = staff_fixture("staff")
    admin = staff_fixture()
    version = install_operations(admin)

    assert {:error, {:live_redirect, %{to: "/o/horizonte/processos"}}} =
             live(login(conn, actor), ~p"/o/horizonte/processos/#{version.workflow_id}")

    assert {:error, :forbidden} =
             operation(actor, "add_resource", %{"name" => "Inválida"})

    assert Operations.workspace(actor, Operations.today(actor)) == nil
  end

  test "menu edits and deactivation survive reload and preserve numeric prices", %{conn: conn} do
    f = operations_fixture()

    {:ok, view, _} =
      live(
        login(conn, f.actor),
        ~p"/o/horizonte/processos/#{Operations.default_workflow(f.actor)}"
      )

    view |> element("#edit-product-#{f.soup}") |> render_click()

    view
    |> form("#product-form",
      product: %{
        name: "Sopa",
        category: "Entradas",
        price: "30,00",
        destination: "Cozinha",
        active: "false"
      }
    )
    |> render_submit()

    {:ok, again, _} =
      live(
        login(conn, f.actor),
        ~p"/o/horizonte/processos/#{Operations.default_workflow(f.actor)}"
      )

    assert has_element?(again, "#products-#{f.soup}", "Indisponível")
    assert has_element?(again, "#products-#{f.soup}", "R$ 30,00")
  end
end
