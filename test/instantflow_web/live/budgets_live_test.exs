defmodule InstantflowWeb.BudgetsLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  import Instantflow.FinanceFixtures
  alias Instantflow.{Finance, WorkflowCatalog.Views}

  defp expose(f) do
    definition =
      Map.put(f.version.definition, "interface", %{
        "pages" => [
          %{
            "key" => "finance",
            "label" => "Financeiro",
            "blocks" => ["finance_setup", "finance_summary"]
          }
        ],
        "finance" => %{
          "account_binding" => "shared_budget",
          "scope" => "shared_account",
          "view_roles" => ["finance"]
        }
      })

    {:ok, version} =
      Instantflow.WorkflowCatalog.publish(
        f.admin,
        definition,
        f.version.bindings,
        f.version.number
      )

    %{f | version: version}
  end

  test "authorized generated finance pages converge and revoke totals", %{conn: conn} do
    f = finance_fixture() |> expose()
    target = ~p"/o/horizonte/processos/#{f.version.workflow_id}/p/finance"
    {:ok, first, _} = live(login(conn, f.finance), target)
    {:ok, second, _} = live(login(build_conn(), f.finance), target)
    assert has_element?(first, "#process-finance-accounts", "10000")

    first
    |> form("#process-finance-allocation",
      finance_allocation: %{
        account_id: f.account.id,
        amount: "500",
        reason: "Complemento fictício"
      }
    )
    |> render_submit()

    assert has_element?(first, "#process-finance-accounts", "10500")
    assert has_element?(second, "#process-finance-accounts", "10500")

    for grant <- Instantflow.Identity.scope(f.finance.user_id, f.finance.organization_id).grants do
      assert {:ok, _} = Instantflow.Access.revoke(f.admin, grant.id)
    end

    assert_redirect(second, "/o/horizonte/processos")
  end

  test "external identities and unrelated staff cannot discover totals or forge allocations", %{
    conn: conn
  } do
    f = finance_fixture() |> expose()
    parent = staff_fixture("parent")

    assert {:error, {:live_redirect, %{to: "/o/horizonte/processos"}}} =
             live(login(conn, parent), ~p"/o/horizonte/processos/#{f.version.workflow_id}")

    assert {:error, :forbidden} =
             Finance.allocate(parent, f.account.id, 900, "Forjado", Ecto.UUID.generate())

    {:ok, view, _} =
      live(
        login(build_conn(), f.requester),
        ~p"/o/horizonte/processos/#{f.version.workflow_id}/p/finance"
      )

    refute has_element?(view, "#process-finance-accounts article")
    refute has_element?(view, "#process-finance-allocation")

    render_hook(view, "finance-allocate", %{
      "finance_allocation" => %{
        "account_id" => to_string(f.account.id),
        "amount" => "900",
        "reason" => "Forjado"
      }
    })

    assert [%{allocated: 10_000}] = Finance.accounts(f.finance)
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
