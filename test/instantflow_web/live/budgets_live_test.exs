defmodule InstantflowWeb.BudgetsLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  import Instantflow.FinanceFixtures
  alias Instantflow.{Finance, WorkflowCatalog.Views}

  test "authorized viewers converge after committed allocations and lose totals after revocation",
       %{conn: conn} do
    f = finance_fixture()
    conn = login(conn, f.finance)
    {:ok, first, _} = live(conn, ~p"/o/horizonte/orcamentos")
    {:ok, second, _} = live(conn, ~p"/o/horizonte/orcamentos")
    assert has_element?(first, "#budget-accounts tr", "10000")

    first
    |> form("#budget-allocation-form",
      allocation: %{account_id: f.account.id, amount: "500", reason: "Complemento fictício"}
    )
    |> render_submit()

    assert has_element?(first, "#budget-accounts tr", "10500")
    assert has_element?(second, "#budget-accounts tr", "10500")
    grants = Instantflow.Identity.scope(f.finance.user_id, f.finance.organization_id).grants
    for grant <- grants, do: Instantflow.Access.revoke(f.admin, grant.id)
    assert has_element?(second, "#budget-count", "0 conta(s)")
    refute has_element?(second, "#budget-accounts tr")
    refute has_element?(second, "#budget-allocation-form")
  end

  test "parent and unrelated staff cannot discover budget totals or forge allocations", %{
    conn: conn
  } do
    f = finance_fixture()

    for actor <- [staff_fixture("parent"), f.requester] do
      {:ok, view, _} = live(login(conn, actor), ~p"/o/horizonte/orcamentos")
      assert has_element?(view, "#budget-count", "0 conta(s)")
      refute has_element?(view, "#budget-accounts tr")
      refute has_element?(view, "#budget-allocation-form")

      render_hook(view, "allocate", %{
        "allocation" => %{
          "account_id" => to_string(f.account.id),
          "amount" => "900",
          "reason" => "Forjado"
        }
      })

      assert [%{allocated: 10_000}] = Finance.accounts(f.finance)
    end
  end

  test "calendar presents permitted trip dates and assignment view includes the current department",
       %{conn: conn} do
    f = finance_fixture("field_trip")
    id = request(f)
    result = Views.search(f.head, f.version.workflow_id, "calendar")
    assert [%{date: "2026-11-12", stage: "finance"}] = result.rows
    assert Views.search(staff_fixture("parent"), f.version.workflow_id, "calendar").total == 0
    {:ok, view, _} = live(login(conn, f.head), ~p"/o/horizonte/solicitacoes")

    view
    |> form("#configured-view-form", view: %{key: "#{f.version.workflow_id}:calendar"})
    |> render_submit()

    assert has_element?(view, "#configured-calendar time", "2026-11-12")
    assert has_element?(view, "#configured-calendar a[href='/o/horizonte/solicitacoes/#{id}']")

    view
    |> form("#configured-view-form", view: %{key: "#{f.version.workflow_id}:assignments"})
    |> render_submit()

    assert has_element?(view, "#configured-table th", "Departamento atribuído")
    assert has_element?(view, "#configured-rows tr", f.head.department.name)
  end
end
