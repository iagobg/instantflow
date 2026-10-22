defmodule Instantflow.Incidents do
  @moduledoc "Restricted incident reporting; curated simulated communication never projects internal notes to families."
  import Ecto.Query
  alias Instantflow.{Repo, Tenant, WorkflowCatalog}
  alias Instantflow.WorkflowCatalog.Version

  def install(actor, departments) do
    definition =
      File.read!(Application.app_dir(:instantflow, "priv/workflows/incident.json"))
      |> Jason.decode!()

    WorkflowCatalog.publish(actor, definition, %{
      "roles" => %{"teacher" => ["teacher"], "dean" => ["dean"], "counselor" => ["counselor"]},
      "departments" => departments
    })
  end

  # Compatibility URL delegates to declared urgency views; copied workflows use
  # the same service without a template-key selector.
  def list(actor, filters) do
    options =
      Instantflow.WorkflowCatalog.Views.options(actor)
      |> Enum.filter(fn option -> option.urgency? end)

    selected =
      Enum.find(options, fn option -> option.id == filters["view"] end) || List.first(options)

    if selected do
      input =
        Map.put(
          filters,
          "fields",
          if(filters["urgency"] in [nil, ""],
            do: %{},
            else: urgency_filter(actor, selected, filters["urgency"])
          )
        )

      result =
        Instantflow.WorkflowCatalog.Views.search(actor, selected.workflow_id, selected.key, input)

      rows =
        Enum.map(result.rows, fn row ->
          location =
            Enum.find_value(row.cells, fn cell ->
              if cell.key != "stage" and cell.value != row.urgency, do: cell.value
            end)

          %{
            id: row.id,
            urgency: row.urgency || "Não informada",
            location: location || "Não informado",
            stage: row.stage,
            stage_label: row.stage_label
          }
        end)

      %{
        rows: rows,
        total: Enum.sum(Enum.map(result.stages, fn stage -> stage.count end)),
        filtered: result.total,
        urgent: result.urgent
      }
    else
      %{rows: [], total: 0, filtered: 0, urgent: 0}
    end
  end

  defp urgency_filter(actor, option, value) do
    Tenant.read(
      actor,
      fn _ ->
        version =
          Repo.all(
            from v in Version,
              where: v.workflow_id == ^option.workflow_id,
              order_by: [desc: v.number]
          )
          |> Enum.find(fn v ->
            Enum.any?(v.definition["views"], fn view ->
              view["key"] == option.key and view["urgency"] != nil
            end)
          end)

        spec =
          version &&
            Enum.find(version.definition["views"], fn view -> view["key"] == option.key end)

        if spec, do: %{spec["urgency"]["field"] => value}, else: %{}
      end,
      %{}
    )
  end
end
