defmodule Instantflow.QuerySourceProbe do
  @moduledoc "Count selected Ecto sources in the caller's controlled read window."
  def capture(sources, fun) do
    counters = Map.new(sources, &{&1, :atomics.new(1, [])})
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:instantflow, :repo, :query],
        &__MODULE__.handle_query/4,
        {self(), counters}
      )

    try do
      result = fun.()
      {result, Map.new(counters, fn {source, counter} -> {source, :atomics.get(counter, 1)} end)}
    after
      :telemetry.detach(handler)
    end
  end

  def handle_query(_, _, metadata, {owner, counters}) do
    if self() == owner do
      if counter = counters[metadata.source], do: :atomics.add(counter, 1, 1)
    end
  end
end
