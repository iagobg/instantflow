defmodule InstantflowWeb.Sprint11OperationalAuthoringTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  alias Instantflow.{Operations, WorkflowCatalog.Templates}

  test "imported independent workspace is mapped and configured in the editor and runs through generated routes",
       %{conn: conn} do
    actor = staff_fixture()
    json = File.read!(Path.expand("../../fixtures/sprint11/supper_room.json", __DIR__))
    {:ok, draft} = Templates.import(actor, json)
    conn = login(conn, actor)
    {:ok, editor, _} = live(conn, ~p"/o/horizonte/modelos/#{draft.id}")
    assert has_element?(editor, "#operational-contract")

    editor
    |> form("#template-mappings",
      mapping: %{
        roles: %{host: ["admin"]},
        departments: %{service_team: actor.department_id},
        assignment: "service_team"
      }
    )
    |> render_submit()

    editor
    |> form("#interface-page-form",
      interface_page: %{
        key: "service_desk",
        label: "Serviço",
        blocks: ~w(catalog resources items batches settlement daily_summary),
        close_transition: "complete_visit",
        payment_methods: ["cash"]
      }
    )
    |> render_submit()

    {:ok, saved} = Templates.get(actor, draft.id)
    assert get_in(saved.definition, ["interface", "operations", "payment_methods"]) == ["cash"]
    refute has_element?(editor, "#publish-template[disabled]")
    editor |> element("#publish-template") |> render_click()
    editor |> element("#confirm-publish-template") |> render_click()

    {:ok, view, _} =
      live(conn, ~p"/o/horizonte/processos/#{draft.workflow_id}/p/service_desk")

    view |> form("#resource-form", resource: %{name: "Mesa 12"}) |> render_submit()
    [resource] = Operations.workspace(actor, Operations.today(actor), draft.workflow_id).resources

    view
    |> form("#open-visit-form",
      visit: %{
        resource_id: resource.id,
        responsible_actor: "Ana",
        business_date: Date.to_iso8601(Operations.today(actor))
      }
    )
    |> render_submit()

    assert has_element?(view, "#active-visit")
    assert has_element?(view, "#checkout_payment_method option[value='cash']")
    refute has_element?(view, "#checkout_payment_method option[value='pix']")
    view |> form("#checkout-form", checkout: %{payment_method: "cash"}) |> render_submit()
    assert has_element?(view, "#visit-settled")
  end
end
