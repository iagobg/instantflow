defmodule Instantflow.Diagnostics.QueryProbe do
  @moduledoc """
  Opt-in, bounded Ecto query aggregates for controlled diagnostic windows.

  `capture/2` returns `{result, report}`. By default only the calling process is
  measured; `scope: :all` includes asynchronous work and unrelated traffic, so
  use it only in an isolated workload. Drain previous notifications first and
  await the measured operation's follow-up work before returning from the block.

  No SQL, parameters, identities or returned values are retained. Binary bytes
  count decoded binary values (including nested JSON), not PostgreSQL wire bytes
  or BEAM memory. Content bytes count the returned `content` column separately.
  Observer overhead is included in wall time. This is not a connection-lease
  measurement or a continuously enabled production reporter.
  """
  use GenServer, restart: :temporary

  @event [:instantflow, :repo, :query]
  @groups [:documents, :history, :authorization, :other]
  @counters [
    :statements,
    :errors,
    :rows,
    :binary_bytes,
    :content_bytes,
    :content_selections,
    :update_locks,
    :total_time,
    :query_time,
    :queue_time,
    :decode_time
  ]
  @times [:total_time, :query_time, :queue_time, :decode_time]
  @time_keys %{
    total_time: :total_time_ms,
    query_time: :query_time_ms,
    queue_time: :queue_time_ms,
    decode_time: :decode_time_ms
  }

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def capture(fun, opts \\ []) when is_function(fun, 0) do
    {:ok, probe} = GenServer.start(__MODULE__, Keyword.put(opts, :owner, self()))
    started = System.monotonic_time()

    try do
      value = fun.()
      duration = System.monotonic_time() - started
      {value, Map.put(finish(probe), :elapsed_ms, milliseconds(duration))}
    after
      GenServer.stop(probe)
    end
  end

  @doc "Ends the measurement window and returns aggregates. Safe to call again."
  def finish(probe), do: GenServer.call(probe, :finish)

  @impl true
  def init(opts) do
    owner = Keyword.fetch!(opts, :owner)
    scope = Keyword.get(opts, :scope, :caller)
    true = is_pid(owner) and scope in [:caller, :all]
    monitor = Process.monitor(owner)
    counters = Map.new(@groups, &{&1, :atomics.new(length(@counters), signed: false)})
    handler = {__MODULE__, make_ref()}
    :ok = :telemetry.attach(handler, @event, &__MODULE__.handle_query/4, {owner, scope, counters})
    {:ok, %{handler: handler, monitor: monitor, counters: counters}}
  end

  @impl true
  def handle_call(:finish, _from, state) do
    :telemetry.detach(state.handler)

    groups = Map.new(state.counters, fn {group, ref} -> {group, counters(ref)} end)

    total =
      Enum.reduce(Map.values(groups), %{}, fn values, acc ->
        Map.merge(acc, values, fn _, a, b -> a + b end)
      end)

    {:reply, Map.put(total, :groups, groups), state}
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, _, _}, %{monitor: monitor} = state),
    do: {:stop, :normal, state}

  @impl true
  def terminate(_, state), do: :telemetry.detach(state.handler)

  @doc false
  def handle_query(_, measurements, metadata, {owner, scope, counters}) do
    if scope == :all or self() == owner do
      {result, errors} =
        case metadata.result do
          {:ok, result} -> {result, 0}
          _ -> {%{}, 1}
        end

      rows = Map.get(result, :rows) || []
      columns = Map.get(result, :columns) || []
      content_index = Enum.find_index(columns, &(&1 == "content"))

      content_bytes =
        if content_index do
          Enum.reduce(rows, 0, fn row, sum -> sum + binary_bytes(Enum.at(row, content_index)) end)
        else
          0
        end

      values = [
        1,
        errors,
        length(rows),
        binary_bytes(rows),
        content_bytes,
        if(content_index, do: 1, else: 0),
        if(String.contains?(metadata.query, "FOR UPDATE"), do: 1, else: 0)
        | Enum.map(@times, &(Map.get(measurements, &1) || 0))
      ]

      ref = Map.fetch!(counters, group(metadata.source))

      Enum.each(Enum.with_index(values, 1), fn {value, index} ->
        :atomics.add(ref, index, value)
      end)
    end
  end

  defp counters(ref) do
    Map.new(Enum.with_index(@counters, 1), fn {key, index} ->
      value = :atomics.get(ref, index)

      if key in @times,
        do: {Map.fetch!(@time_keys, key), milliseconds(value)},
        else: {key, value}
    end)
  end

  # Fixed output keys and fixed group cardinality, even for arbitrary raw queries.
  defp group("private_documents"), do: :documents
  defp group("transition_events"), do: :history

  defp group(source) when source in ["users", "memberships", "membership_grants", "sessions"],
    do: :authorization

  defp group(_), do: :other

  defp binary_bytes(value) when is_binary(value), do: byte_size(value)

  defp binary_bytes(value) when is_list(value),
    do: Enum.reduce(value, 0, &(binary_bytes(&1) + &2))

  defp binary_bytes(%_{}), do: 0

  defp binary_bytes(value) when is_map(value),
    do:
      Enum.reduce(value, 0, fn {key, item}, sum ->
        sum + binary_bytes(key) + binary_bytes(item)
      end)

  defp binary_bytes(_), do: 0

  defp milliseconds(native), do: System.convert_time_unit(native, :native, :microsecond) / 1000
end
