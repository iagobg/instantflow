defmodule Instantflow.Delivery.Worker do
  @moduledoc "Polling recovery worker; business state remains in PostgreSQL, with no per-ticket process."
  use GenServer
  require Logger
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def init(opts) do
    send(self(), :poll)

    {:ok,
     Keyword.get(
       opts,
       :interval,
       Application.get_env(:instantflow, :delivery_poll_interval_ms, 250)
     )}
  end

  def handle_info(:poll, interval) do
    try do
      Instantflow.Delivery.drain()
    rescue
      _ -> Logger.warning("outbox_poll_failed")
    end

    Process.send_after(self(), :poll, interval)
    {:noreply, interval}
  end
end
