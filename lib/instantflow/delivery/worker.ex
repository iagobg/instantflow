defmodule Instantflow.Delivery.Worker do
  @moduledoc "Polling recovery worker; business state remains in PostgreSQL, with no per-ticket process."
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
           Application.get_env(:instantflow, :delivery_poll_interval_ms, 250)
         )
     }}
  end

  def handle_info(:poll, state) do
    state =
      try do
        %{state | cursor: Instantflow.Delivery.drain_page(state.cursor).cursor}
      rescue
        _ ->
          Logger.warning("outbox_poll_failed")
          state
      end

    Process.send_after(self(), :poll, state.interval)
    {:noreply, state}
  end
end
