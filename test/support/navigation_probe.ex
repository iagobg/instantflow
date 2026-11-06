defmodule Instantflow.NavigationProbe do
  @moduledoc "Count bounded navigation label projections without retaining SQL or parameters."
  def capture(pid, fun) do
    counter = :atomics.new(1, [])
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:instantflow, :repo, :query],
        &__MODULE__.handle_query/4,
        {pid, counter}
      )

    try do
      result = fun.()
      {result, :atomics.get(counter, 1)}
    after
      :telemetry.detach(handler)
    end
  end

  def handle_query(_, _, metadata, {pid, counter}) do
    if self() == pid and String.contains?(metadata.query, "->>'name'") and
         String.contains?(metadata.query, "LIMIT 25"),
       do: :atomics.add(counter, 1, 1)
  end
end
