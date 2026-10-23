defmodule Instantflow.WorkflowCatalogTest do
  use Instantflow.DataCase, async: true
  import Instantflow.WorkflowFixtures
  alias Instantflow.{WorkflowCatalog, WorkflowRuntime}
  alias Instantflow.WorkflowCatalog.{Definition, Version}

  test "publication rejects invalid definitions, unresolved bindings and non-administrators" do
    f = workflow_fixture()

    assert {:error, :forbidden} =
             WorkflowCatalog.publish(f.requester, f.definition, f.bindings, 1)

    assert {:error, :invalid_bindings} = WorkflowCatalog.publish(f.admin, f.definition, %{}, 1)
    invalid = put_in(f.definition, ["transitions", Access.at(0), "actors"], [])

    assert {:error, {:invalid_definition, _}} =
             WorkflowCatalog.publish(f.admin, invalid, f.bindings, 1)

    assert Repo.aggregate(Version, :count) == 1
  end

  test "terminal forms cannot allow silent edits" do
    definition =
      put_in(
        definition_fixture(),
        ["sections", Access.at(0), "access", Access.at(0), "edit_stages"],
        ["approved"]
      )

    assert {:error, _} = Definition.validate(definition)
  end

  test "configuration access grants no automatic request access" do
    f = workflow_fixture()
    id = create_ticket(f)
    assert {:error, :not_found} = WorkflowRuntime.get(f.admin, id)
    assert WorkflowRuntime.search(f.admin).tickets == []
  end
end
