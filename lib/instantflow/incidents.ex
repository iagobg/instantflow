defmodule Instantflow.Incidents do
  @moduledoc "Restricted incident reporting; curated simulated communication never projects internal notes to families."
  alias Instantflow.{Repo, Tenant, WorkflowCatalog, WorkflowRuntime}
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

  def list(actor, filters) do
    Tenant.read(
      actor,
      fn a ->
        rows =
          WorkflowRuntime.list(a)
          |> Enum.flat_map(fn ticket ->
            version = Repo.get!(Version, ticket.workflow_version_id)

            if version.definition["template_key"] == "incident" do
              case WorkflowRuntime.get(a, ticket.id) do
                {:ok, data} ->
                  report = Enum.find(data.sections, &(&1.key == "report"))

                  if report,
                    do: [
                      %{
                        id: ticket.id,
                        urgency: report.values["urgency"] || "Não informada",
                        stage: ticket.stage,
                        stage_label:
                          Enum.find(version.definition["stages"], &(&1["key"] == ticket.stage))[
                            "label"
                          ],
                        location: report.values["location"] || "Não informado"
                      }
                    ],
                    else: []

                _ ->
                  []
              end
            else
              []
            end
          end)

        filtered =
          Enum.filter(rows, fn row ->
            (filters["urgency"] in [nil, ""] or row.urgency == filters["urgency"]) and
              (filters["stage"] in [nil, ""] or row.stage == filters["stage"])
          end)

        rank = %{"Urgente" => 0, "Prioritária" => 1, "Rotina" => 2}

        %{
          total: length(rows),
          urgent:
            Enum.count(rows, &(&1.urgency == "Urgente" and &1.stage not in ~w(closed cancelled))),
          filtered: length(filtered),
          rows:
            filtered |> Enum.sort_by(&{Map.get(rank, &1.urgency, 3), -&1.id}) |> Enum.take(100)
        }
      end,
      %{total: 0, urgent: 0, filtered: 0, rows: []}
    )
  end
end
