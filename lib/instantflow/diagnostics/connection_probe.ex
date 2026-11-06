defmodule Instantflow.Diagnostics.ConnectionProbe do
  @moduledoc """
  Opt-in connection occupancy measurement for an isolated, quiescent runtime pool.

  Uses a private OTP trace session and DBConnection 2.10's checkout boundaries.
  Only function arities, fixed markers and monotonic timestamps are traced: no
  arguments, return values, SQL, credentials or row data. Nothing is installed
  until `capture/2` is called. Requires OTP 27+ and a single ConnectionPool (not
  Sandbox or partitioned pools). Start before any measured leases and await all
  follow-up work before returning. Unmatched boundaries and overflow invalidate
  the report. Observer overhead is included; this is not production monitoring.

  Waiting runs from checkout entry until successful acquisition. Holding runs
  from acquisition until checkin/disconnect/stop entry, excluding the final
  holder handoff bookkeeping. Sum of holding time includes overlapping leases;
  dividing by elapsed time gives average occupied connections, not CPU usage.
  """
  use GenServer, restart: :temporary

  def start_link(opts), do: GenServer.start_link(__MODULE__, target(opts))

  def capture(fun, opts \\ []) do
    {:ok, probe} = GenServer.start(__MODULE__, target(Keyword.put(opts, :owner, self())))

    try do
      result = fun.()
      ended = System.monotonic_time()
      {result, GenServer.call(probe, {:finish, ended}, 30_000)}
    after
      GenServer.stop(probe)
    end
  end

  defp target(opts) do
    repo = Keyword.get(opts, :repo, Instantflow.Repo)
    Keyword.put(opts, :repo_pid, repo.get_dynamic_repo())
  end

  @impl true
  def init(opts) do
    repo = Keyword.get(opts, :repo, Instantflow.Repo)
    %{pid: pool, opts: pool_opts} = Ecto.Adapter.lookup_meta(Keyword.fetch!(opts, :repo_pid))

    unless pool_opts[:pool] == DBConnection.ConnectionPool and
             Keyword.get(repo.config(), :pool_count, 1) == 1 do
      raise ArgumentError, "connection probe requires a single real ConnectionPool"
    end

    Code.ensure_loaded!(DBConnection)
    limit = Keyword.get(opts, :max_events, 100_000)
    true = is_integer(limit) and limit in 1..1_000_000
    session = :trace.session_create(__MODULE__, self(), [])
    connection = %{__struct__: DBConnection, pool_ref: {:pool_ref, pool, :_, :_, :_, :_}}

    try do
      pattern(session, :checkout, 3, [{[pool, :_, :_], [], []}])

      pattern(session, :past_event, 3, [
        {[:_, :checkin, :_], [], [{:message, :acquired}]},
        {[:_, :checkout, :_], [], [{:message, :checkout_done}]}
      ])

      for {function, arity} <- [checkin: 1, disconnect: 2, stop: 4] do
        pattern(session, function, arity, [
          {[connection | List.duplicate(:_, arity - 1)], [], []}
        ])
      end

      :trace.process(session, :all, true, [:call, :arity, :monotonic_timestamp])

      {:ok,
       %{
         session: session,
         owner: Process.monitor(Keyword.fetch!(opts, :owner)),
         started: System.monotonic_time(),
         pending: %{},
         active: %{},
         intervals: [],
         waits: [],
         failures: 0,
         unmatched: 0,
         events: 0,
         limit: limit,
         overflow: false,
         finishing: nil
       }}
    rescue
      error ->
        :trace.session_destroy(session)
        reraise error, __STACKTRACE__
    end
  end

  defp pattern(session, function, arity, spec) do
    1 = :trace.function(session, {DBConnection, function, arity}, spec, [:local])
  end

  @impl true
  def handle_call({:finish, ended}, from, state) do
    :trace.process(state.session, :all, false, [:call])
    barrier = :trace.delivered(state.session, :all)
    {:noreply, %{state | finishing: {barrier, from, ended}}}
  end

  @impl true
  def handle_info({:trace_delivered, :all, barrier}, %{finishing: {barrier, from, ended}} = s) do
    :trace.session_destroy(s.session)
    GenServer.reply(from, report(s, ended))
    {:noreply, s}
  end

  def handle_info({:DOWN, monitor, :process, _, _}, %{owner: monitor} = s),
    do: {:stop, :normal, s}

  def handle_info({:trace_ts, pid, :call, {DBConnection, function, _}, time}, s),
    do: event(s, pid, function, time)

  def handle_info({:trace_ts, pid, :call, {DBConnection, :past_event, 3}, marker, time}, s),
    do: event(s, pid, marker, time)

  @impl true
  def terminate(_, s), do: :trace.session_destroy(s.session)

  defp event(%{overflow: true} = s, _, _, _), do: {:noreply, s}

  defp event(%{events: n, limit: n} = s, _, _, _) do
    :trace.process(s.session, :all, false, [:call])
    {:noreply, %{s | overflow: true}}
  end

  defp event(s, pid, kind, time) do
    {:noreply, record(%{s | events: s.events + 1}, pid, kind, time)}
  end

  defp record(s, pid, :checkout, time),
    do: %{s | pending: Map.put(s.pending, pid, time)}

  defp record(s, pid, :acquired, time) do
    case Map.pop(s.pending, pid) do
      {nil, _} ->
        s

      {started, pending} ->
        %{
          s
          | pending: pending,
            active: Map.put(s.active, pid, time),
            waits: [time - started | s.waits]
        }
    end
  end

  defp record(s, pid, :checkout_done, time) do
    case Map.pop(s.pending, pid) do
      {nil, _} ->
        s

      {started, pending} ->
        %{s | pending: pending, failures: s.failures + 1, waits: [time - started | s.waits]}
    end
  end

  defp record(s, pid, kind, time) when kind in [:checkin, :disconnect, :stop] do
    case Map.pop(s.active, pid) do
      {nil, _} -> %{s | unmatched: s.unmatched + 1}
      {started, active} -> %{s | active: active, intervals: [{started, time} | s.intervals]}
    end
  end

  defp report(s, ended) do
    durations = Enum.map(s.intervals, fn {a, b} -> b - a end)
    outside = Enum.count(s.intervals, fn {a, b} -> a < s.started or b > ended end)
    held = Enum.sum(durations)
    elapsed = ended - s.started

    {_, peak} =
      s.intervals
      |> Enum.flat_map(fn {a, b} -> [{a, 1}, {b, -1}] end)
      |> Enum.sort()
      |> Enum.reduce({0, 0}, fn {_, change}, {busy, peak} ->
        {busy + change, max(peak, busy + change)}
      end)

    %{
      complete:
        not s.overflow and s.unmatched == 0 and s.active == %{} and s.pending == %{} and
          outside == 0,
      overflow: s.overflow,
      outside_window: outside,
      unfinished: map_size(s.active) + map_size(s.pending),
      unmatched_releases: s.unmatched,
      leases: length(durations),
      failed_checkouts: s.failures,
      elapsed_ms: ms(elapsed),
      held_ms: ms(held),
      wait_ms: ms(Enum.sum(s.waits)),
      max_held_ms: ms(Enum.max(durations, fn -> 0 end)),
      max_wait_ms: ms(Enum.max(s.waits, fn -> 0 end)),
      peak_occupied: peak,
      average_occupied: if(elapsed > 0, do: held / elapsed, else: 0)
    }
  end

  defp ms(native), do: System.convert_time_unit(native, :native, :microsecond) / 1000
end
