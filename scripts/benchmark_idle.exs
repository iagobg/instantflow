defmodule Instantflow.IdleBenchmark do
  @moduledoc false
  alias Instantflow.{OperatorRepo, Repo}
  alias Instantflow.Diagnostics.QueryProbe

  def run do
    duration = integer_env("IDLE_BENCHMARK_DURATION_MS", 600_000, 1_000..3_600_000)
    organizations = integer_env("IDLE_BENCHMARK_ORGANIZATIONS", 10, 1..10_000)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:postgrex)
    config = OperatorRepo.config() |> Keyword.take([:username, :password, :hostname, :port])

    unless config[:hostname] in ["localhost", "127.0.0.1"],
      do: raise("This probe only creates local disposable databases")

    {:ok, control} = Postgrex.start_link(config ++ [database: "postgres"])
    database = "instantflow_idle_" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
    Postgrex.query!(control, "CREATE DATABASE #{database} TEMPLATE template0 ENCODING 'UTF8'")

    report =
      try do
        prepare(database, organizations)

        repo_config =
          Repo.config()
          |> Keyword.delete(:url)
          |> Keyword.merge(
            database: database,
            username: "instantflow_runtime",
            password: System.get_env("RUNTIME_DB_PASSWORD", "instantflow-runtime-local-only"),
            pool: DBConnection.ConnectionPool,
            pool_size: 10
          )

        Application.put_env(:instantflow, Repo, repo_config)

        for key <- [
              :delivery_worker,
              :maintenance_worker,
              :calculation_worker,
              :calculation_execution
            ],
            do: Application.put_env(:instantflow, key, false)

        {:ok, _} = Application.ensure_all_started(:instantflow)

        try do
          [["instantflow_runtime", false, false]] =
            Repo.query!(
              "SELECT current_user, rolsuper, rolbypassrls FROM pg_roles WHERE rolname=current_user"
            ).rows

          [[postgres]] = Repo.query!("SHOW server_version").rows
          observation = observe(duration)

          Map.merge(observation, %{
            organizations: organizations,
            pool_size: 10,
            postgres: postgres,
            requested_duration_ms: duration,
            delivery_interval_ms:
              Application.get_env(:instantflow, :delivery_poll_interval_ms, 250),
            maintenance_interval_ms:
              Application.get_env(:instantflow, :maintenance_interval_ms, 60_000),
            environment:
              "Local disposable database; real non-owner runtime login; two independently supervised workers",
            limitations:
              "Idle query/work counts only; concurrent local activity may affect timings. No hosted capacity claim. Binary bytes are decoded values, not wire traffic."
          })
        after
          Application.stop(:instantflow)
        end
      after
        Postgrex.query!(control, "DROP DATABASE #{database}")
        GenServer.stop(control)
      end

    path = System.get_env("IDLE_BENCHMARK_REPORT", ".local/idle-benchmark.json")
    File.mkdir_p!(Path.dirname(path))

    File.write!(
      path,
      Jason.encode!(Map.put(report, :disposable_database_removed, true), pretty: true) <> "\n"
    )

    IO.puts("Idle benchmark complete: #{path}")
  end

  defp prepare(database, organizations) do
    {:ok, owner} =
      OperatorRepo.start_link(name: :idle_benchmark_operator, database: database, pool_size: 2)

    OperatorRepo.put_dynamic_repo(owner)

    try do
      Ecto.Migrator.run(
        OperatorRepo,
        Application.app_dir(:instantflow, "priv/repo/migrations"),
        :up,
        all: true,
        log: false
      )

      now = DateTime.utc_now(:second)

      rows =
        for n <- 1..organizations,
            do: %{
              slug: "idle-#{n}",
              name: "Synthetic",
              status: "active",
              timezone: "UTC",
              inserted_at: now,
              updated_at: now
            }

      rows
      |> Enum.chunk_every(500)
      |> Enum.each(&OperatorRepo.insert_all(Instantflow.Identity.Organization, &1))
    after
      Supervisor.stop(owner)
      OperatorRepo.put_dynamic_repo(OperatorRepo)
    end
  end

  defp observe(duration) do
    counters = :atomics.new(4, signed: false)
    handler = {__MODULE__, make_ref()}
    events = [[:instantflow, :delivery, :pass], [:instantflow, :maintenance, :pass]]
    :ok = :telemetry.attach_many(handler, events, &__MODULE__.pass/4, counters)

    try do
      {_, report} =
        QueryProbe.capture(
          fn ->
            {:ok, supervisor} =
              Supervisor.start_link(
                [
                  Instantflow.Delivery.Worker,
                  Instantflow.Maintenance.Worker
                ],
                strategy: :one_for_one
              )

            try do
              # A real elapsed-time diagnostic window, not a timing assertion in a test.
              Process.sleep(duration)
            after
              Supervisor.stop(supervisor)
            end
          end,
          scope: :all
        )

      Map.put(report, :passes, %{
        delivery: :atomics.get(counters, 1),
        maintenance: :atomics.get(counters, 2),
        delivery_failures: :atomics.get(counters, 3),
        maintenance_failures: :atomics.get(counters, 4)
      })
    after
      :telemetry.detach(handler)
    end
  end

  def pass([:instantflow, kind, :pass], measurements, _, counters) do
    index = if kind == :delivery, do: 1, else: 2
    :atomics.add(counters, index, 1)
    :atomics.add(counters, index + 2, measurements.failures)
  end

  defp integer_env(key, default, range) do
    value = String.to_integer(System.get_env(key, to_string(default)))
    unless value in range, do: raise("#{key} outside supported range")
    value
  end
end

Instantflow.IdleBenchmark.run()
