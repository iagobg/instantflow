defmodule Instantflow.WorkflowCatalog.Views do
  @moduledoc "Configured table/board projections use each ticket's pinned version and readable sections."
  import Ecto.Query
  alias Instantflow.{Repo, Tenant, WorkflowRuntime}
  alias Instantflow.WorkflowCatalog.Version
  alias Instantflow.WorkflowRuntime.Policy

  def options(actor) do
    Tenant.read(
      actor,
      fn a ->
        WorkflowRuntime.list(a)
        |> Enum.flat_map(fn ticket ->
          version = Repo.get!(Version, ticket.workflow_version_id)

          version.definition["views"]
          |> Enum.filter(fn view -> readable_columns(a, ticket, version, view) != [] end)
          |> Enum.map(fn view ->
            %{
              id: "#{ticket.workflow_id}:#{view["key"]}",
              label: "#{version.definition["name"]} · #{view["label"]}"
            }
          end)
        end)
        |> Enum.uniq_by(& &1.id)
      end,
      []
    )
  end

  def search(actor, workflow_id, key, filters \\ %{}) do
    Tenant.read(
      actor,
      fn a ->
        result = WorkflowRuntime.search(a, Map.put(filters, "workflow_id", workflow_id))

        rows =
          Enum.flat_map(result.tickets, fn ticket ->
            version = Repo.get!(Version, ticket.workflow_version_id)
            view = Enum.find(version.definition["views"], &(&1["key"] == key))

            if view do
              columns = readable_columns(a, ticket, version, view)

              sections =
                Repo.all(
                  from s in Instantflow.WorkflowRuntime.Section, where: s.ticket_id == ^ticket.id
                )
                |> Map.new(&{&1.key, &1.values})

              cells =
                Enum.map(columns, fn column ->
                  value =
                    case column.key do
                      "stage" ->
                        stage_label(version, ticket)

                      "assigned_department" ->
                        Repo.get!(Instantflow.Identity.Department, ticket.assigned_department_id).name

                      _ ->
                        get_in(sections, String.split(column.key, "."))
                    end

                  Map.put(column, :value, value)
                end)

              if cells == [],
                do: [],
                else: [
                  %{
                    id: ticket.id,
                    type: view["type"],
                    label: view["label"],
                    stage: ticket.stage,
                    stage_label: stage_label(version, ticket),
                    date:
                      Enum.find_value(cells, fn c ->
                        if get_in(
                             Instantflow.WorkflowCatalog.Definition.fields(version.definition),
                             [c.key, "type"]
                           ) == "date", do: c.value
                      end),
                    cells: cells
                  }
                ]
            else
              []
            end
          end)

        %{
          rows: Enum.sort_by(rows, &{&1.date || "9999-12-31", &1.id}),
          total: result.filtered,
          columns:
            rows
            |> Enum.flat_map(& &1.cells)
            |> Enum.uniq_by(& &1.key)
            |> Enum.map(&Map.take(&1, [:key, :label])),
          stages:
            rows
            |> Enum.map(
              &%{id: &1.stage, label: &1.stage_label, count: Map.get(result.counts, &1.stage, 0)}
            )
            |> Enum.uniq_by(& &1.id)
        }
      end,
      %{rows: [], total: 0, columns: [], stages: []}
    )
  end

  defp readable_columns(actor, ticket, version, view) do
    Enum.flat_map(view["columns"], fn
      "stage" ->
        [%{key: "stage", label: "Etapa"}]

      "assigned_department" ->
        [%{key: "assigned_department", label: "Departamento atribuído"}]

      ref ->
        [section_key, field_key] = String.split(ref, ".")
        section = Enum.find(version.definition["sections"], &(&1["key"] == section_key))
        field = section && Enum.find(section["fields"], &(&1["key"] == field_key))

        if field && Policy.section?(actor, ticket, version, section, :read),
          do: [%{key: ref, label: field["label"]}],
          else: []
    end)
  end

  defp stage_label(version, ticket),
    do: Enum.find(version.definition["stages"], &(&1["key"] == ticket.stage))["label"]
end
