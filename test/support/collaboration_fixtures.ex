defmodule Instantflow.CollaborationFixtures do
  alias Instantflow.WorkflowCatalog
  import Instantflow.WorkflowFixtures

  def collaborative_definition do
    definition = definition_fixture()
    [section] = definition["sections"]

    section =
      Map.update!(section, "access", fn access ->
        Enum.map(access, &Map.put(&1, "edit_stages", ["draft", "review"]))
      end)

    notes = section |> Map.put("key", "notes") |> Map.put("label", "Notas da equipe")

    restricted =
      notes
      |> Map.put("key", "finance")
      |> Map.put("label", "Parecer financeiro reservado")
      |> Map.put("classification", "restricted")
      |> Map.put("access", [
        %{
          "role" => "finance",
          "scope" => "assigned_department",
          "read" => true,
          "edit_stages" => ["draft", "review"]
        }
      ])

    definition
    |> Map.put("sections", [section, notes, restricted])
    |> Map.update!("role_requirements", &(&1 ++ [%{"key" => "finance", "label" => "Financeiro"}]))
    |> Map.update!("transitions", fn edges ->
      Enum.map(edges, fn edge ->
        if edge["key"] == "approve",
          do:
            edge
            |> Map.put("finance_sensitive", true)
            |> Map.put("disallow_requester", false)
            |> Map.put("guard", nil),
          else: edge
      end)
    end)
  end

  def collaborative_fixture do
    f = workflow_fixture()
    bindings = put_in(f.bindings, ["roles", "finance"], ["finance"])
    {:ok, version} = WorkflowCatalog.publish(f.admin, collaborative_definition(), bindings, 1)
    %{f | version: version, bindings: bindings, definition: collaborative_definition()}
  end

  def section_command(data, section, values, key \\ key()) do
    row = Enum.find(data.sections, &(&1.key == section))

    %{
      "operation" => "save_section",
      "key" => key,
      "ticket_id" => data.ticket.id,
      "section" => section,
      "values" => values,
      "expected_stage_revision" => data.ticket.stage_revision,
      "expected_section_revision" => row.revision
    }
  end
end
