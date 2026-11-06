defmodule InstantflowWeb.RefreshNotifications do
  @moduledoc "Combine already queued invalidations before the current authorized refresh."
  @max_queued 100
  @process_refreshes [
    :reconcile,
    :permissions_changed,
    :workspaces_changed,
    :requests_changed,
    :operations_changed,
    :budgets_changed
  ]

  def coalesce(%{view: InstantflowWeb.ProcessLive}, message) when message in @process_refreshes,
    do: drain_process(@max_queued)

  def coalesce(
        %{
          view: InstantflowWeb.RequestLive,
          assigns: %{current_scope: %{organization_id: org}, data: %{ticket: %{id: id}}}
        },
        message
      ) do
    case message do
      {:ticket_changed, ^org, ^id} ->
        drain_record(org, id, @max_queued)

      event when event in [:reconcile, :permissions_changed] ->
        drain_record(org, id, @max_queued)

      %Phoenix.Socket.Broadcast{event: "presence_diff", topic: topic} ->
        if topic == Instantflow.Collaboration.Presence.topic(org, id),
          do: drain_presence(topic, @max_queued),
          else: :ok

      _ ->
        :ok
    end
  end

  def coalesce(_, _), do: :ok

  # Only interchangeable invalidations are consumed. Each surviving callback
  # still validates its session and reads the current projection. Calls, browser
  # events, access-revoked notifications and periodic revalidation remain queued.
  # No delay is introduced, and the cap bounds each drain under sustained load.
  defp drain_record(_, _, 0), do: :ok

  defp drain_record(org, id, remaining) do
    receive do
      {:ticket_changed, ^org, ^id} ->
        drain_record(org, id, remaining - 1)

      event when event in [:reconcile, :permissions_changed] ->
        drain_record(org, id, remaining - 1)
    after
      0 -> :ok
    end
  end

  defp drain_process(0), do: :ok

  defp drain_process(remaining) do
    receive do
      message when message in @process_refreshes -> drain_process(remaining - 1)
    after
      0 -> :ok
    end
  end

  defp drain_presence(_, 0), do: :ok

  defp drain_presence(topic, remaining) do
    receive do
      %Phoenix.Socket.Broadcast{topic: ^topic, event: "presence_diff"} ->
        drain_presence(topic, remaining - 1)
    after
      0 -> :ok
    end
  end
end
