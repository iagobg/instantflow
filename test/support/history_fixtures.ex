defmodule Instantflow.HistoryFixtures do
  @moduledoc "Synthetic immutable event history for bounded projection tests."
  import Ecto.Query
  alias Instantflow.Repo
  alias Instantflow.WorkflowRuntime.{Event, Ticket}

  def append(actor, ticket_id, revisions, operation \\ "save:request") do
    now = DateTime.utc_now(:second)

    rows =
      Enum.map(revisions, fn revision ->
        %{
          organization_id: actor.organization_id,
          ticket_id: ticket_id,
          actor_id: actor.user_id,
          operation: operation,
          from_stage: "draft",
          to_stage: "draft",
          revision: revision,
          details: %{},
          inserted_at: now,
          updated_at: now
        }
      end)

    events =
      rows
      |> Enum.chunk_every(500)
      |> Enum.flat_map(fn batch ->
        {_, events} = Repo.insert_all(Event, batch, returning: true)
        events
      end)

    Repo.update_all(from(t in Ticket, where: t.id == ^ticket_id),
      set: [revision: Enum.max(revisions)]
    )

    events
  end

  def deliveries(events) do
    Enum.map(events, fn event ->
      Repo.insert!(%Instantflow.Delivery.Message{
        organization_id: event.organization_id,
        ticket_id: event.ticket_id,
        event_id: event.id,
        key: Ecto.UUID.generate(),
        kind: "simulate_notification",
        behavior: "success",
        status: "failed"
      })
    end)
  end
end
