defmodule Instantflow.WorkflowCatalog.RetirementPublicationTest do
  use ExUnit.Case, async: true
  alias Instantflow.WorkflowCatalog.Definition

  test "retired execution modules and APIs cannot be selected by the maintained runtime" do
    for module <- [
          Instantflow.Enrollment,
          Instantflow.Incidents,
          Instantflow.WorkflowRuntime.LegacyAccess,
          Instantflow.WorkflowRuntime.LegacyResets,
          Instantflow.PrivateDocuments.LegacyPolicy,
          Instantflow.WorkflowCatalog.LegacyWorkspaces
        ] do
      refute Code.ensure_loaded?(module)
    end

    refute {:list, 1} in Instantflow.WorkflowRuntime.__info__(:functions)
    refute {:today, 0} in Instantflow.Operations.__info__(:functions)
  end

  test "supported example replacements use explicit participants and document policies" do
    for key <- ~w(enrollment incident) do
      assert :ok = Definition.validate(Instantflow.Examples.definition(key))
    end
  end

  test "new definitions cannot enter implicit guardian or document compatibility" do
    for name <- ~w(enrollment incident) do
      legacy =
        File.read!(Path.expand("../../fixtures/history/#{name}.json", __DIR__)) |> Jason.decode!()

      assert {:error, errors} = Definition.validate(legacy)

      assert Enum.any?(
               errors,
               &(String.contains?(&1, "document_policy") or String.contains?(&1, ".scope"))
             )
    end

    definition = Instantflow.WorkflowFixtures.definition_fixture()
    assert :ok = Definition.validate(definition)

    invalid =
      update_in(
        definition,
        ["sections", Access.at(0), "fields"],
        &(&1 ++ [%{"key" => "file", "label" => "Arquivo", "type" => "attachment"}])
      )

    assert {:error, errors} = Definition.validate(invalid)
    assert Enum.any?(errors, &String.contains?(&1, "document_policy"))
  end
end
