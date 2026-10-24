defmodule Instantflow.WorkflowCatalog.Flows do
  @moduledoc "Read-only published diagrams using workspace and pinned record authorization."
  alias Instantflow.{Tenant, WorkflowRuntime}
  alias Instantflow.WorkflowCatalog.{Retirement, Workspaces}
  alias Instantflow.WorkflowRuntime.ParticipantPages

  def get(actor, workflow_id), do: get(actor, workflow_id, nil)

  def get(actor, workflow_id, ticket_id) when is_integer(workflow_id) and workflow_id > 0 do
    Tenant.read(
      actor,
      fn fresh ->
        case source(fresh, workflow_id, ticket_id) do
          {:ok, version, ticket} ->
            {:ok, project(fresh, version, ticket)}

          _ ->
            {:error, :not_found}
        end
      end,
      {:error, :not_found}
    )
  end

  def get(_, _, _), do: {:error, :not_found}

  defp source(actor, workflow_id, nil) do
    case Workspaces.get(actor, workflow_id) do
      nil -> {:error, :not_found}
      version -> {:ok, version, nil}
    end
  end

  defp source(actor, workflow_id, id) when is_integer(id) and id > 0 do
    # Participant pages have a separately curated projection. A staff diagram must
    # never become an alternate route around that published audience contract.
    with :default <- ParticipantPages.route(actor, id),
         {:ok, data} <- WorkflowRuntime.get(actor, id),
         true <- data.ticket.workflow_id == workflow_id do
      {:ok, data.version, data.ticket}
    else
      _ -> {:error, :not_found}
    end
  end

  defp source(_, _, _), do: {:error, :not_found}

  defp project(actor, version, ticket) do
    definition = version.definition

    transitions =
      if ticket do
        # Runtime.get already applies Policy.history? to this pinned record.
        definition["transitions"]
      else
        # An overview has no requester/assignment facts. Actor-private history
        # paths are shown only in an authorized case projection or the editor.
        Enum.reject(definition["transitions"], &(&1["history_visibility"] == "actors"))
      end

    %{
      workflow_id: version.workflow_id,
      version_id: version.id,
      number: version.number,
      name: definition["name"],
      published_at: version.inserted_at,
      archived?: Retirement.retired?(version.id),
      can_author?: actor.role == "admin",
      ticket_id: ticket && ticket.id,
      current_stage: ticket && ticket.stage,
      definition: %{
        "stages" => Enum.map(definition["stages"], &Map.take(&1, ~w(key label initial terminal))),
        "transitions" => Enum.map(transitions, &Map.take(&1, ~w(key label from to kind)))
      }
    }
  end
end
