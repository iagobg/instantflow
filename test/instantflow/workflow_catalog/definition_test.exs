defmodule Instantflow.WorkflowCatalog.DefinitionTest do
  use ExUnit.Case, async: true
  import Instantflow.WorkflowFixtures
  alias Instantflow.WorkflowCatalog.Definition

  test "minimal approval fixture validates" do
    assert :ok = Definition.validate(definition_fixture())
  end

  test "unreachable stages, duplicate keys, ambiguous entries and no terminal path fail" do
    definition = definition_fixture()
    orphan = %{"key" => "orphan", "label" => "Órfã", "initial" => false, "terminal" => false}
    assert {:error, _} = Definition.validate(update_in(definition["stages"], &(&1 ++ [orphan])))
    assert {:error, _} = Definition.validate(update_in(definition["stages"], &(&1 ++ [hd(&1)])))

    assert {:error, _} =
             Definition.validate(put_in(definition, ["stages", Access.at(1), "initial"], true))

    assert {:error, _} =
             Definition.validate(
               update_in(
                 definition["transitions"],
                 &Enum.filter(&1, fn t -> t["to"] not in ~w(approved rejected cancelled) end)
               )
             )
  end

  test "forged references, unregistered actions, executable properties and actorless transitions fail" do
    definition = definition_fixture()

    for changed <- [
          put_in(definition, ["transitions", Access.at(0), "required_fields"], ["request.unknown"]),
          put_in(definition, ["transitions", Access.at(0), "actions"], [
            %{"type" => "run_sql", "behavior" => "success"}
          ]),
          put_in(definition, ["transitions", Access.at(0), "actors"], []),
          Map.put(definition, "javascript", "alert(1)"),
          put_in(definition, ["sections", Access.at(0), "fields", Access.at(0), "type"], "html")
        ],
        do: assert({:error, _} = Definition.validate(changed))
  end

  test "guards reject incompatible values, unknown fields and unsupported operators" do
    for guard <- [
          %{"op" => "eq", "field" => "request.summary", "value" => 42},
          %{"op" => "present", "field" => "request.unknown"},
          %{"op" => "eval", "field" => "request.summary"},
          %{"op" => "gt", "field" => "request.summary", "value" => "text"}
        ] do
      assert {:error, _} =
               Definition.validate(
                 put_in(definition_fixture(), ["transitions", Access.at(0), "guard"], guard)
               )
    end
  end

  test "typed values enforce integer money, ISO dates, booleans and enumerations" do
    assert Definition.valid_value?(%{"type" => "money"}, 1250)
    refute Definition.valid_value?(%{"type" => "money"}, 12.50)
    refute Definition.valid_value?(%{"type" => "money"}, -1)
    assert Definition.valid_value?(%{"type" => "date"}, "2026-10-20")
    refute Definition.valid_value?(%{"type" => "date"}, "2026-02-30")
    assert Definition.valid_value?(%{"type" => "boolean"}, false)
    refute Definition.valid_value?(%{"type" => "boolean"}, "false")
    refute Definition.valid_value?(%{"type" => "multiple_choice", "options" => ["A"]}, ["B"])
    refute Definition.valid_value?(%{"type" => "directory_reference"}, 123)
    assert Definition.present?(false)
    refute Definition.present?("   ")
  end
end
