defmodule Instantflow.WorkflowCatalog.BuilderContractTest do
  use ExUnit.Case, async: true
  alias Instantflow.WorkflowCatalog.{Capabilities, Definition, Interface, Interchange, Schema}

  test "capabilities compose as a set, while unknown, duplicate and missing-core contracts fail" do
    definition = example("requisition")

    for capabilities <- [
          ["core", "finance", "operations"],
          ["operations", "core", "finance"],
          ["finance", "operations", "core"]
        ] do
      composed =
        definition
        |> Map.put("capabilities", capabilities)
        |> put_in(
          ["interface", "operations"],
          Instantflow.WorkflowCatalog.OperationalContract.defaults()
        )
        |> put_in(["interface", "lifecycle"], %{"close_transition" => "finish"})

      assert :ok = Definition.validate(composed)
      assert {:ok, ^composed} = composed |> Interchange.encode() |> Interchange.decode()
    end

    for capabilities <- [["finance"], ["core", "core"], ["core", "unknown"]] do
      assert {:error, _} = Definition.validate(Map.put(definition, "capabilities", capabilities))
    end
  end

  test "portable schema and builder registries expose the same bounded vocabulary" do
    schema = Schema.document()
    assert schema["properties"]["capabilities"]["items"]["enum"] == Capabilities.supported()

    assert get_in(schema, [
             "properties",
             "interface",
             "properties",
             "pages",
             "items",
             "properties",
             "blocks",
             "items",
             "enum"
           ]) == Interface.blocks()

    for block <- Interface.blocks() do
      assert is_binary(Interface.block_label(block))
      assert Interface.required_capability(block) in Capabilities.supported()
    end
  end

  test "page composition rejects undeclared capabilities, blocks and roles at the shared boundary" do
    definition = example("simple_approval")
    page = %{"key" => "workspace", "label" => "Trabalho", "blocks" => ["catalog"]}
    invalid = Map.put(definition, "interface", %{"pages" => [page]})
    assert {:error, _} = Definition.validate(invalid)

    invalid = put_in(invalid, ["interface", "pages"], [Map.put(page, "blocks", ["restaurant"])])
    assert {:error, _} = Definition.validate(invalid)

    invalid = put_in(definition, ["interface", "access"], %{"view" => ["undeclared_role"]})
    assert {:error, _} = Definition.validate(invalid)
  end

  defp example(key) do
    Application.app_dir(:instantflow, "priv/workflows/" <> key <> ".json")
    |> File.read!()
    |> Jason.decode!()
  end
end
