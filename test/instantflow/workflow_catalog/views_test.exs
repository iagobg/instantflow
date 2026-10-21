defmodule Instantflow.WorkflowCatalog.ViewsTest do
  use Instantflow.DataCase, async: true
  import Instantflow.WorkflowFixtures
  alias Instantflow.{Access, WorkflowCatalog}
  alias Instantflow.WorkflowCatalog.Views

  test "configured views strip unreadable fields and honor grant revocation and pinned versions" do
    f = Instantflow.CollaborationFixtures.collaborative_fixture()

    view = %{
      "key" => "finance_board",
      "label" => "Quadro",
      "type" => "board",
      "columns" => ["stage", "request.summary", "finance.summary"]
    }

    definition = Map.put(f.definition, "views", [view])
    {:ok, version} = WorkflowCatalog.publish(f.admin, definition, f.bindings, 2)
    f = %{f | version: version}
    id = create_ticket(f)

    Repo.update_all(
      from(s in Instantflow.WorkflowRuntime.Section,
        where: s.ticket_id == ^id and s.key == "finance"
      ),
      set: [values: %{"summary" => "RESERVADO"}]
    )

    [option] = Views.options(f.requester)
    assert option.id == "#{version.workflow_id}:finance_board"
    result = Views.search(f.requester, version.workflow_id, "finance_board")
    assert [%{type: "board"} = row] = result.rows
    assert Enum.map(row.cells, & &1.key) == ["stage", "request.summary"]
    refute inspect(result) =~ "RESERVADO"
    refute inspect(result) =~ "finance.summary"

    {:ok, {_, grant}} =
      Access.grant(f.admin, f.requester.id, f.requester.department_id, "finance")

    assert [%{cells: cells}] =
             Views.search(f.requester, version.workflow_id, "finance_board").rows

    assert Enum.any?(cells, &(&1.value == "RESERVADO"))
    Access.revoke(f.admin, grant.id)
    refute inspect(Views.search(f.requester, version.workflow_id, "finance_board")) =~ "RESERVADO"
    changed = put_in(definition, ["views", Elixir.Access.at(0), "type"], "table")
    {:ok, _} = WorkflowCatalog.publish(f.admin, changed, f.bindings, 3)

    assert [%{type: "board"}] =
             Views.search(f.requester, version.workflow_id, "finance_board").rows

    assert Views.search(f.requester, version.workflow_id + 1000, "finance_board").rows == []
  end
end
