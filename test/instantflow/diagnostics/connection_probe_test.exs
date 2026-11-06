defmodule Instantflow.Diagnostics.ConnectionProbeTest do
  use ExUnit.Case, async: false
  alias Instantflow.{Repo, Diagnostics.ConnectionProbe}

  setup do
    runtime =
      start_supervised!(
        {Repo, name: :connection_probe_test, pool: DBConnection.ConnectionPool, pool_size: 1}
      )

    Repo.put_dynamic_repo(runtime)
    Repo.query!("SELECT 1")
    tasks = start_supervised!(Task.Supervisor)
    %{runtime: runtime, tasks: tasks, pool: Ecto.Adapter.lookup_meta(runtime).pid}
  end

  test "counts real leases, including application work and nested transactions" do
    {_, report} =
      ConnectionProbe.capture(fn ->
        Repo.checkout(fn ->
          Repo.query!("SELECT $1::text", ["private-parameter"])

          {:ok, :ok} =
            Repo.transaction(fn ->
              Repo.query!("SELECT 2")
              :ok
            end)

          Repo.query!("SELECT 3")
        end)

        Repo.query!("SELECT 4")
      end)

    assert report.complete
    assert report.leases == 2
    assert report.peak_occupied == 1
    assert report.held_ms > 0
    assert report.wait_ms >= 0
    refute inspect(report) =~ "private-parameter"
  end

  test "counts queued callers and release after callback exceptions", c do
    parent = self()

    {_, report} =
      ConnectionProbe.capture(fn ->
        first =
          Task.Supervisor.async_nolink(c.tasks, fn ->
            Repo.put_dynamic_repo(c.runtime)

            Repo.checkout(fn ->
              send(parent, :holding)
              receive do: (:release -> :ok)
            end)
          end)

        assert_receive :holding

        second =
          Task.Supervisor.async_nolink(c.tasks, fn ->
            Repo.put_dynamic_repo(c.runtime)
            Repo.query!("SELECT 1")
          end)

        await_queued(c.pool, System.monotonic_time(:millisecond) + 2_000)
        send(first.pid, :release)
        Task.await(first)
        Task.await(second)

        assert_raise RuntimeError, "intentional", fn ->
          Repo.checkout(fn -> raise "intentional" end)
        end
      end)

    assert report.complete
    assert report.leases == 3
    assert report.peak_occupied == 1
    assert report.wait_ms > 0
  end

  test "independent sessions and cleanup on raised capture" do
    {inner, outer} =
      ConnectionProbe.capture(fn ->
        {_, inner} = ConnectionProbe.capture(fn -> Repo.query!("SELECT 1") end)
        assert_raise RuntimeError, fn -> ConnectionProbe.capture(fn -> raise "stop" end) end
        Repo.query!("SELECT 2")
        inner
      end)

    assert inner.complete and outer.complete
    assert inner.leases == 1
    assert outer.leases == 2
  end

  test "measures overlapping holders and excludes another pool", c do
    runtime =
      start_supervised!(
        Supervisor.child_spec(
          {Repo,
           name: :connection_probe_parallel, pool: DBConnection.ConnectionPool, pool_size: 2},
          id: :parallel_repo
        )
      )

    Repo.put_dynamic_repo(runtime)
    Repo.query!("SELECT 1")
    parent = self()

    {_, report} =
      ConnectionProbe.capture(fn ->
        holders =
          for _ <- 1..2 do
            Task.Supervisor.async_nolink(c.tasks, fn ->
              Repo.put_dynamic_repo(runtime)

              Repo.checkout(fn ->
                send(parent, :holding)
                receive do: (:release -> :ok)
              end)
            end)
          end

        assert_receive :holding
        assert_receive :holding
        Repo.put_dynamic_repo(c.runtime)
        Repo.query!("SELECT 42")
        Repo.put_dynamic_repo(runtime)
        Enum.each(holders, &send(&1.pid, :release))
        Enum.each(holders, &Task.await/1)
      end)

    assert report.complete
    assert report.leases == 2
    assert report.peak_occupied == 2
  end

  test "reports checkout failure without mistaking it for a lease", c do
    parent = self()

    {_, report} =
      ConnectionProbe.capture(fn ->
        holder =
          Task.Supervisor.async_nolink(c.tasks, fn ->
            Repo.put_dynamic_repo(c.runtime)

            Repo.checkout(fn ->
              send(parent, :holding)
              receive do: (:release -> :ok)
            end)
          end)

        assert_receive :holding

        assert {:error, %DBConnection.ConnectionError{}} =
                 Repo.query("SELECT 1", [], queue: false)

        send(holder.pid, :release)
        Task.await(holder)
      end)

    assert report.complete
    assert report.leases == 1
    assert report.failed_checkouts == 1
  end

  test "overflow explicitly invalidates a bounded report" do
    {_, report} = ConnectionProbe.capture(fn -> Repo.query!("SELECT 1") end, max_events: 1)
    refute report.complete
    assert report.overflow
  end

  test "unfinished asynchronous work invalidates the report", c do
    parent = self()

    {holder, report} =
      ConnectionProbe.capture(fn ->
        holder =
          Task.Supervisor.async_nolink(c.tasks, fn ->
            Repo.put_dynamic_repo(c.runtime)

            Repo.checkout(fn ->
              send(parent, :holding)
              receive do: (:release -> :ok)
            end)
          end)

        assert_receive :holding
        holder
      end)

    refute report.complete
    assert report.unfinished == 1
    send(holder.pid, :release)
    Task.await(holder)
  end

  test "owner death removes instrumentation", c do
    owner =
      Task.Supervisor.async_nolink(c.tasks, fn ->
        receive do: (:finish -> :ok)
      end)

    probe =
      start_supervised!(%{
        id: :owned_probe,
        start: {__MODULE__, :start_probe, [c.runtime, owner.pid]},
        restart: :temporary
      })

    monitor = Process.monitor(probe)
    send(owner.pid, :finish)
    Task.await(owner)
    assert_receive {:DOWN, ^monitor, :process, ^probe, _}
  end

  # The observer resolves dynamic repositories in its starting process, here
  # the test supervisor. Keep that process's prior repository setting intact.
  def start_probe(runtime, owner) do
    previous = Repo.put_dynamic_repo(runtime)

    try do
      ConnectionProbe.start_link(owner: owner)
    after
      Repo.put_dynamic_repo(previous)
    end
  end

  defp await_queued(pool, deadline) do
    case DBConnection.get_connection_metrics(pool) do
      [%{checkout_queue_length: n}] when n > 0 ->
        :ok

      _ ->
        assert System.monotonic_time(:millisecond) < deadline
        await_queued(pool, deadline)
    end
  end
end
