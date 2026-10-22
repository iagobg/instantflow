defmodule InstantflowWeb.FinanceSurfacesLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  alias Instantflow.{FinanceFixtures, Repo}
  alias Instantflow.WorkflowCatalog.Templates

  test "finance setup, binding scope and explicit reset are authored and operated through common pages",
       %{conn: conn} do
    f = FinanceFixtures.finance_fixture()
    {:ok, draft} = Templates.clone(f.admin, f.version.id)
    {:ok, editor, _} = live(login(conn, f.admin), ~p"/o/horizonte/modelos/#{draft.id}")

    editor
    |> form("#template-finance-account",
      new_finance_account: %{
        name: "Conta local configurada",
        department_id: f.admin.department_id
      }
    )
    |> render_submit()

    assert has_element?(
             editor,
             "#mapping-budget-shared_budget option",
             "Conta local configurada"
           )

    editor
    |> form("#interface-page-form",
      interface_page: %{
        key: "overview",
        label: "Gestão",
        blocks: ["records", "finance_setup", "finance_summary"],
        finance_binding: "shared_budget",
        finance_scope: "shared_account",
        finance_roles: ["finance"],
        access_view: ["finance"]
      }
    )
    |> render_submit()

    editor |> element("#edit-transitions-root-revise_purchase") |> render_click()

    editor
    |> form("#template-item-form",
      item: %{
        reset_enabled: "true",
        reset_sections: ["order", "delivery"],
        invalidate_approvals: []
      }
    )
    |> render_submit()

    refute has_element?(editor, "#publish-template[disabled]")
    editor |> element("#publish-template") |> render_click()
    {:ok, saved} = Templates.get(f.admin, draft.id)
    version = Repo.get!(Instantflow.WorkflowCatalog.Version, saved.published_version_id)

    {:ok, page, _} =
      live(
        login(Phoenix.ConnTest.build_conn(), f.finance),
        ~p"/o/horizonte/processos/#{version.workflow_id}"
      )

    assert has_element?(page, "#process-finance-summary", "Disponível: 10000")
    assert has_element?(page, "#process-finance-allocation")
    refute has_element?(page, "#process-finance-account")

    page
    |> form("#process-finance-allocation",
      finance_allocation: %{account_id: f.account.id, amount: "500", reason: "Alocação sintética"}
    )
    |> render_submit()

    assert has_element?(page, "#process-finance-summary", "Disponível: 10500")
  end
end
