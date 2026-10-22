defmodule Instantflow.WorkflowRuntime.ConfiguredViewsTest do
  use Instantflow.DataCase, async: true
  import Instantflow.WorkflowFixtures
  alias Instantflow.{Access, BuilderFixtures}
  alias Instantflow.WorkflowCatalog.{Views, Definition}
  alias Instantflow.WorkflowRuntime.Section

  test "hidden sort/filter/urgency data cannot influence rows, choices or counts; grants reauthorize" do
    f = Instantflow.CollaborationFixtures.collaborative_fixture()

    definition =
      f.definition
      |> Map.put("template_key", "independent_priority_queue")
      |> update_in(
        ["sections", Elixir.Access.at(2), "fields"],
        &(&1 ++
            [
              %{
                "key" => "priority",
                "label" => "Prioridade",
                "type" => "single_choice",
                "options" => ["Alta", "Baixa"]
              }
            ])
      )
      |> Map.put("views", [
        %{
          "key" => "queue",
          "label" => "Fila",
          "type" => "board",
          "columns" => ["stage", "request.summary", "finance.priority"],
          "filters" => ["finance.priority"],
          "sort" => %{"field" => "urgency", "direction" => "asc"},
          "urgency" => %{"field" => "finance.priority", "values" => ["Alta", "Baixa"]}
        }
      ])

    version = BuilderFixtures.install(f.admin, definition, f.bindings)
    f = %{f | version: version}
    low = create_ticket(f)
    high = create_ticket(f)

    Repo.update_all(from(s in Section, where: s.ticket_id == ^low and s.key == "finance"),
      set: [values: %{"priority" => "Alta"}]
    )

    Repo.update_all(from(s in Section, where: s.ticket_id == ^high and s.key == "finance"),
      set: [values: %{"priority" => "Baixa"}]
    )

    result = Views.search(f.requester, version.workflow_id, "queue")
    assert Enum.map(result.rows, & &1.id) == [high, low]
    assert result.filters == [] and result.urgent == 0

    assert Views.search(f.requester, version.workflow_id, "queue", %{
             "fields" => %{"finance.priority" => "Alta"}
           }).total == 0

    {:ok, {_, grant}} =
      Access.grant(f.admin, f.requester.id, f.requester.department_id, "finance")

    result = Views.search(f.requester, version.workflow_id, "queue")
    assert Enum.map(result.rows, & &1.id) == [low, high]
    assert result.urgent == 1
    assert [%{ref: "finance.priority", values: ["Alta", "Baixa"]}] = result.filters

    assert [%{id: ^low}] =
             Views.search(f.requester, version.workflow_id, "queue", %{
               "fields" => %{"finance.priority" => "Alta"}
             }).rows

    Access.revoke(f.admin, grant.id)
    assert Views.search(f.requester, version.workflow_id, "queue").filters == []
  end

  test "calendar dates remain civil dates, instants are batched in organization timezone and undated rows survive" do
    f = workflow_fixture()

    definition =
      f.definition
      |> Map.put("template_key", "schedule_queue")
      |> update_in(
        ["sections", Elixir.Access.at(0), "fields"],
        &(&1 ++
            [
              %{"key" => "day", "label" => "Data", "type" => "date"},
              %{"key" => "moment", "label" => "Instante", "type" => "datetime"}
            ])
      )
      |> Map.put("views", [
        %{
          "key" => "dates",
          "label" => "Agenda",
          "type" => "calendar",
          "columns" => ["stage"],
          "calendar_field" => "request.day",
          "sort" => %{"field" => "request.day", "direction" => "asc"}
        },
        %{
          "key" => "instants",
          "label" => "Instantes",
          "type" => "calendar",
          "columns" => ["stage"],
          "calendar_field" => "request.moment"
        }
      ])

    version = BuilderFixtures.install(f.admin, definition, f.bindings)
    f = %{f | version: version}
    dated = create_ticket(f)
    undated = create_ticket(f)

    assert {:ok, _} =
             save(
               f.requester,
               dated,
               Map.merge(values(), %{"day" => "2026-11-12", "moment" => "2026-11-12T12:00:00Z"})
             )

    assert [%{id: ^dated, date: "2026-11-12", date_kind: "date"}, %{id: ^undated, date: nil}] =
             Views.search(f.requester, version.workflow_id, "dates").rows

    assert Enum.any?(
             Views.search(f.requester, version.workflow_id, "instants").rows,
             &(&1.date == "12/11/2026 09:00 (America/Sao_Paulo)")
           )

    invalid =
      put_in(definition, ["views", Elixir.Access.at(0), "calendar_field"], "request.summary")

    assert {:error, _} = Definition.validate(invalid)
  end

  test "named assignment filtering and projection preserve confidential section authority under independent keys" do
    f = Instantflow.IncidentFixtures.incident_fixture()
    definition = f.version.definition |> Map.put("template_key", "independent_support_queue")
    version = BuilderFixtures.install(f.admin, definition, f.version.bindings)
    f = %{f | version: version}
    id = Instantflow.IncidentFixtures.report(f)

    assert {:ok, _} =
             Instantflow.IncidentFixtures.assign(f.dean, id, f.counselor.id, "Atribuição")

    assert [%{id: ^id}] =
             Views.search(f.counselor, version.workflow_id, "triage", %{"assigned_to" => "me"}).rows

    assert Views.search(f.other_counselor, version.workflow_id, "triage", %{"assigned_to" => "me"}).total ==
             0

    assert Views.search(f.admin, version.workflow_id, "triage").total == 0
    result = Views.search(f.dean, version.workflow_id, "triage")
    assert result.assignment? and hd(result.rows).assignment
    refute Enum.any?(result.columns, &(&1.key == "support.notes"))
  end
end
