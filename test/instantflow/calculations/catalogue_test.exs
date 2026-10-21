defmodule Instantflow.Calculations.CatalogueTest do
  use Instantflow.DataCase, async: false
  alias Instantflow.Calculations.Catalogue
  alias Instantflow.{Access, CalculationFixtures, Tenant}
  import Instantflow.IdentityFixtures

  setup do
    Application.put_env(:instantflow, :calculation_execution, true)
    Application.put_env(:instantflow, :calculation_runner, CalculationFixtures)
    CalculationFixtures.switch(true)

    on_exit(fn ->
      Application.delete_env(:instantflow, :calculation_execution)
      Application.delete_env(:instantflow, :calculation_runner)
    end)

    :ok
  end

  test "administration cannot author or activate without independent grants; immutable content and fixture review" do
    admin = staff_fixture()
    assert {:error, :forbidden} = Catalogue.register(admin, CalculationFixtures.attrs())
    {:ok, _} = Access.grant(admin, admin.id, admin.department_id, "python_author")
    assert {:ok, script} = Catalogue.register(admin, CalculationFixtures.attrs())
    assert {:error, :forbidden} = Catalogue.activate(admin, script.id, true)
    {:ok, _} = Access.grant(admin, admin.id, admin.department_id, "python_reviewer")
    assert {:error, :fixture_failed} = Catalogue.activate(admin, script.id, true)
    assert {:ok, :verified} = Catalogue.verify(admin, script.id)
    assert {:ok, :ok} = Catalogue.activate(admin, script.id, true)
    assert {:error, :forbidden} = Catalogue.source(admin, script.id)
    {:ok, _} = Access.grant(admin, admin.id, admin.department_id, "python_source")
    assert {:ok, original} = Catalogue.source(admin, script.id)
    assert original.source == CalculationFixtures.attrs()["source"]
    assert {:ok, repeated} = Catalogue.register(admin, CalculationFixtures.attrs())
    assert repeated.id == script.id
    changed = Map.put(CalculationFixtures.attrs(), "source", original.source <> "# new version")
    assert {:ok, newer} = Catalogue.register(admin, changed)
    refute newer.digest == script.digest
    assert {:ok, [%{enabled: false}, %{enabled: true}]} = Catalogue.list(admin)

    assert {:error, :invalid_script} =
             Catalogue.register(admin, Map.put(changed, "packages", ["requests"]))

    assert {:error, :invalid_script} =
             Catalogue.register(
               admin,
               put_in(changed, ["input_schema", "participants", "type"], "float")
             )

    assert {:error, :unavailable} = Tenant.raw(999_999, fn -> [] end)
  end

  test "global disablement prevents fixture execution" do
    admin = staff_fixture()

    for role <- ~w(python_author python_reviewer),
        do: Access.grant(admin, admin.id, admin.department_id, role)

    {:ok, script} = Catalogue.register(admin, CalculationFixtures.attrs())
    CalculationFixtures.switch(false)
    assert {:error, :execution_disabled} = Catalogue.verify(admin, script.id)
  end
end
