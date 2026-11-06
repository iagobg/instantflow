defmodule Instantflow.Maintenance.Worker do
  @moduledoc "Periodic retention recovery; each pass visits a rotating bounded page of due tenants."
  use GenServer
  require Logger

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def init(opts) do
    send(self(), :poll)

    {:ok,
     %{
       cursor: 0,
       interval:
         Keyword.get(
           opts,
           :interval,
           Application.get_env(:instantflow, :maintenance_interval_ms, 60_000)
         )
     }}
  end

  def handle_info(:poll, state) do
    state =
      try do
        %{state | cursor: Instantflow.Maintenance.sweep(state.cursor).cursor}
      rescue
        _ ->
          Logger.warning("retention_poll_failed")
          state
      end

    Process.send_after(self(), :poll, state.interval)
    {:noreply, state}
  end
end
