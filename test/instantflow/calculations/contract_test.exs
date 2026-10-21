defmodule Instantflow.Calculations.ContractTest do
  use Instantflow.DataCase, async: false
  alias Instantflow.{CalculationFixtures, WorkflowCatalog}
  alias Instantflow.WorkflowCatalog.{Definition, Interchange, Templates}
  alias Instantflow.Calculations.Catalogue

  setup do
    Application.put_env(:instantflow, :calculation_execution, true)
    Application.put_env(:instantflow, :calculation_runner, CalculationFixtures)
    CalculationFixtures.switch(true)

    on_exit(fn ->
      Application.delete_env(:instantflow, :calculation_execution)
      Application.delete_env(:instantflow, :calculation_runner)
    end)

    %{f: f} = CalculationFixtures.fixture()
    %{f: f}
  end

  test "workflow import retains symbolic references and cannot activate inline source", %{f: f} do
    json = f.definition |> Map.put("template_key", "imported_calculation") |> Interchange.encode()
    assert {:ok, draft} = Templates.import(f.admin, json)
    assert draft.bindings == %{"roles" => %{}, "departments" => %{}}

    assert {:error, :invalid_bindings} =
             WorkflowCatalog.publish(f.admin, draft.definition, draft.bindings)

    source =
      update_in(f.definition["transitions"], fn list ->
        Enum.map(list, fn t ->
          if t["calculation"], do: put_in(t, ["calculation", "source"], "print(1)"), else: t
        end)
      end)

    assert {:error, _} = Definition.validate(source)
    assert {:ok, [script]} = Catalogue.list(f.admin)
    assert {:ok, :ok} = Catalogue.activate(f.admin, script.id, false)

    assert {:error, :invalid_calculation} =
             WorkflowCatalog.publish(f.admin, f.definition, f.bindings, 2)
  end

  test "readers cannot be broadened and waiting stages cannot bypass required results", %{f: f} do
    broadened =
      update_in(f.definition["sections"], fn sections ->
        Enum.map(sections, fn section ->
          if section["key"] == "quotation",
            do:
              Map.update!(
                section,
                "access",
                &[
                  %{
                    "role" => "reviewer",
                    "scope" => "requester",
                    "read" => true,
                    "edit_stages" => []
                  }
                  | &1
                ]
              ),
            else: section
        end)
      end)

    assert {:error, _} = Definition.validate(broadened)

    bypass =
      update_in(f.definition["transitions"], fn edges ->
        Enum.map(edges, &Map.delete(&1, "requires_calculation"))
      end)

    assert {:error, _} = Definition.validate(bypass)

    editable =
      update_in(f.definition["sections"], fn sections ->
        Enum.map(sections, fn s ->
          if s["key"] == "quotation",
            do: put_in(s, ["access", Access.at(0), "edit_stages"], ["draft"]),
            else: s
        end)
      end)

    assert {:error, _} = Definition.validate(editable)
  end
end
