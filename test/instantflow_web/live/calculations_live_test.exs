defmodule InstantflowWeb.CalculationsLiveTest do
  use InstantflowWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  alias Instantflow.{Access, CalculationFixtures}
  alias Instantflow.Calculations.Catalogue

  test "catalogue is unavailable to administrators without script grants", %{conn: conn} do
    admin = staff_fixture()

    assert {:error, {:live_redirect, %{to: "/o/horizonte"}}} =
             live(login(conn, admin), ~p"/o/horizonte/calculos")
  end

  test "registration is inactive and source access is cleared after revocation", %{conn: conn} do
    admin = staff_fixture()
    {:ok, _} = Access.grant(admin, admin.id, admin.department_id, "python_author")
    {:ok, {_, grant}} = Access.grant(admin, admin.id, admin.department_id, "python_source")
    {:ok, view, _} = live(login(conn, admin), ~p"/o/horizonte/calculos")
    attrs = CalculationFixtures.attrs()

    upload =
      file_input(view, "#script-form", :script_file, [
        %{name: "trip.py", content: attrs["source"], type: "text/x-python"}
      ])

    render_upload(upload, "trip.py")

    form(view, "#script-form",
      script: %{
        key: attrs["key"],
        runtime: attrs["runtime"],
        source: "",
        input_schema: Jason.encode!(attrs["input_schema"]),
        output_schema: Jason.encode!(attrs["output_schema"]),
        fixtures: Jason.encode!(attrs["fixtures"]),
        allowed_roles: Jason.encode!(attrs["allowed_roles"])
      }
    )
    |> render_submit()

    {:ok, [script]} = Catalogue.list(admin)
    assert has_element?(view, "#source-script-#{script.id}")
    refute has_element?(view, "#activate-script-#{script.id}")
    view |> element("#source-script-#{script.id}") |> render_click()
    assert has_element?(view, "#script-source")
    assert {:ok, _} = Access.revoke(admin, grant.id)
    render(view)
    refute has_element?(view, "#script-source")
  end

  test "request displays queued calculation status without snapshots or editable outputs", %{
    conn: conn
  } do
    Application.put_env(:instantflow, :calculation_execution, true)
    Application.put_env(:instantflow, :calculation_runner, CalculationFixtures)

    on_exit(fn ->
      Application.delete_env(:instantflow, :calculation_execution)
      Application.delete_env(:instantflow, :calculation_runner)
    end)

    CalculationFixtures.switch(true)
    %{f: f, id: id} = CalculationFixtures.fixture()
    {:ok, view, _} = live(login(conn, f.requester), ~p"/o/horizonte/solicitacoes/#{id}")
    assert has_element?(view, "#calculation-status")
    assert has_element?(view, "#calculation-runs article strong", "Na fila")
    refute has_element?(view, "#section-form-quotation")
  end
end
