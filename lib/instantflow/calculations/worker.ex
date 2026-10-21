defmodule Instantflow.Calculations.Worker do
  @moduledoc "Independent bounded worker: one job per tenant, two tenants concurrently, rotating dispatch."
  use GenServer
  require Logger
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def init(_),
    do:
      (
        send(self(), :poll)
        {:ok, %{tasks: %{}, cursor: 0}}
      )

  def handle_info(:poll, state) do
    state =
      try do
        %{rows: rows} = Instantflow.Repo.query!("SELECT id FROM dispatch_organizations()")
        ids = Enum.map(rows, &hd/1) |> Enum.sort()

        ordered =
          Enum.filter(ids, &(&1 > state.cursor)) ++ Enum.filter(ids, &(&1 <= state.cursor))

        Enum.reduce(ordered, state, fn id, acc ->
          if map_size(acc.tasks) < 2 and id not in Map.values(acc.tasks) do
            task =
              Task.Supervisor.async_nolink(Instantflow.Calculations.Tasks, fn ->
                Instantflow.Calculations.process(id)
              end)

            %{acc | tasks: Map.put(acc.tasks, task.ref, id), cursor: id}
          else
            acc
          end
        end)
      rescue
        _ ->
          Logger.warning("calculation_poll_failed")
          state
      end

    Process.send_after(self(), :poll, 500)
    {:noreply, state}
  end

  def handle_info({ref, _result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, %{state | tasks: Map.delete(state.tasks, ref)}}
  end

  def handle_info({:DOWN, ref, :process, _, _}, state),
    do: {:noreply, %{state | tasks: Map.delete(state.tasks, ref)}}
end
