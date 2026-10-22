defmodule Instantflow.WorkflowCatalog.DiagnosticsTest do
  use ExUnit.Case, async: true
  alias Instantflow.WorkflowCatalog.{Capabilities, Definition, Interchange, Templates}

  test "semantic reference and capability failures identify definition paths" do
    d = Templates.starter("test_contract", "Contrato")

    cases = [
      {put_in(d, ["transitions", Access.at(0), "to"], "missing"), "modelo.transitions[0].to"},
      {put_in(d, ["transitions", Access.at(0), "required_fields"], ["missing.value"]),
       "modelo.transitions[0].required_fields"},
      {put_in(d, ["sections", Access.at(0), "access", Access.at(0), "role"], "missing"),
       "modelo.sections[0].access[0].role"},
      {Map.put(d, "interface", %{
         "pages" => [%{"key" => "parts", "label" => "Peças", "blocks" => ["catalog"]}]
       }), "modelo.interface.pages[0].blocks"}
    ]

    for {invalid, path} <- cases do
      assert {:ok, imported} = invalid |> Interchange.encode() |> Interchange.decode()
      assert {:error, errors} = Definition.validate(invalid)
      assert Definition.validate(imported) == {:error, errors}
      assert Enum.any?(errors, &String.starts_with?(&1, path))
    end
  end

  test "every closed capability declares ownership, dependencies and version policy" do
    assert Enum.map(Capabilities.descriptors(), & &1.id) == Capabilities.supported()

    for descriptor <- Capabilities.descriptors() do
      assert descriptor.version == 1
      assert Code.ensure_loaded?(descriptor.owner)
      assert descriptor.tables != []
      assert descriptor.migration == :immutable_versions
      assert Enum.all?(descriptor.dependencies, &(&1 in Capabilities.supported()))
      assert Enum.all?(descriptor.conflicts, &(&1 in Capabilities.supported()))
    end

    assert Capabilities.descriptor("unknown") == nil
  end

  test "portable validators cannot depend on tenant contexts or example implementations" do
    root = Path.expand("../../../lib/instantflow/workflow_catalog", __DIR__)

    pure =
      ~w(definition diagnostics calculation_contract capabilities interface interchange schema)

    for file <- pure do
      ast = root |> Path.join(file <> ".ex") |> File.read!() |> Code.string_to_quoted!()

      Macro.prewalk(ast, fn
        {:alias, _, [{:__aliases__, _, [:Instantflow | rest]} | _]} = node ->
          assert hd(rest) == :WorkflowCatalog,
                 "forbidden context alias in #{file}: #{inspect(rest)}"

          node

        {{:., _, [{:__aliases__, _, [:Instantflow | rest]}, _]}, _, _} = node ->
          assert hd(rest) == :WorkflowCatalog,
                 "forbidden context call in #{file}: #{inspect(rest)}"

          node

        node ->
          node
      end)
    end
  end

  test "migrated runtime and participant paths use the explicit legacy adapter" do
    root = Path.expand("../../../lib/instantflow", __DIR__)

    for file <- ~w(workflow_runtime.ex workflow_runtime/policy.ex participants.ex) do
      ast = root |> Path.join(file) |> File.read!() |> Code.string_to_quoted!()

      Macro.prewalk(ast, fn
        {:__aliases__, _, [:Instantflow, example | _]} = node ->
          refute example in [:Enrollment, :Incidents], "forbidden example dependency in #{file}"
          node

        node ->
          node
      end)
    end
  end
end
