defmodule Instantflow.TimestampProbe do
  @moduledoc "Count timestamp formatting calls across a controlled LiveView test window."
  def capture(fun) do
    counter = :atomics.new(1, [])
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:instantflow, :repo, :query],
        &__MODULE__.handle_query/4,
        counter
      )

    try do
      result = fun.()
      {result, :atomics.get(counter, 1)}
    after
      :telemetry.detach(handler)
    end
  end

  def handle_query(_, _, metadata, counter) do
    if String.contains?(metadata.query, "to_char(timezone("), do: :atomics.add(counter, 1, 1)
  end
end
