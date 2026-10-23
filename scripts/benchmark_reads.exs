defmodule Instantflow.ReadBenchmark do
  @moduledoc false
  alias Instantflow.{Repo, OperatorRepo, Identity}
  alias Instantflow.Identity.{Organization, Department, Membership, User}
  alias Instantflow.WorkflowCatalog.{Workflow, Version, Definition, Views, Workspaces}
  alias Instantflow.WorkflowRuntime.{Ticket, Section, Projections}

  def run do
    for key <- [:delivery_worker, :calculation_worker, :calculation_execution],
        do: Application.put_env(:instantflow, key, false)

    {:ok, _} = Application.ensure_all_started(:instantflow)

    dimensions = %{
      versions: number("READ_VERSIONS", 1),
      processes: number("READ_PROCESSES", 1),
      used_versions: number("READ_USED_VERSIONS", 1),
      hidden: number("READ_HIDDEN", 0),
      width: number("READ_WIDTH", 1),
      iterations: number("READ_ITERATIONS", 20),
      shape: System.get_env("READ_SHAPE", "equal"),
      surface: System.get_env("READ_SURFACE", "view")
    }

    unless dimensions.iterations in 1..1000 and dimensions.versions in [1, 10, 100] and
             dimensions.processes in [1, 10, 100] and
             dimensions.used_versions in 1..dimensions.versions and
             dimensions.hidden in [0, 9, 99] and dimensions.width in [1, 10, 50] and
             dimensions.shape in ["equal", "uneven"] and
             dimensions.surface in ["view", "options", "search", "catalog"],
           do: raise("unsupported benchmark dimensions")

    config = OperatorRepo.config() |> Keyword.take([:username, :password, :hostname, :port])
    {:ok, control} = Postgrex.start_link(config ++ [database: "postgres"])

    database =
      "instantflow_read_benchmark_" <> Base.encode16(:crypto.strong_rand_bytes(5), case: :lower)

    Postgrex.query!(control, "CREATE DATABASE #{database} TEMPLATE template0 ENCODING 'UTF8'")

    {:ok, owner} =
      OperatorRepo.start_link(name: :read_benchmark_owner, database: database, pool_size: 2)

    OperatorRepo.put_dynamic_repo(owner)

    Ecto.Migrator.run(
      OperatorRepo,
      Application.app_dir(:instantflow, "priv/repo/migrations"),
      :up,
      all: true,
      log: false
    )

    {:ok, runtime} =
      Repo.start_link(
        name: :read_benchmark_runtime,
        database: database,
        username: "instantflow_runtime",
        password: System.get_env("RUNTIME_DB_PASSWORD", "instantflow-runtime-local-only"),
        pool: DBConnection.ConnectionPool,
        pool_size: 10,
        queue_target: 1000,
        queue_interval: 1000
      )

    Repo.put_dynamic_repo(runtime)

    hash =
      User.changeset(%User{email: "synthetic@example.invalid"}, %{
        name: "Synthetic",
        password: "read-benchmark-fictional-only"
      })
      |> Ecto.Changeset.get_change(:password_hash)

    clients = Enum.flat_map(1..10, &populate(&1, hash, dimensions))

    row_counts = %{
      tickets: OperatorRepo.aggregate(Ticket, :count),
      organizations: OperatorRepo.aggregate(Organization, :count),
      staff: length(clients),
      versions: OperatorRepo.aggregate(Version, :count),
      processes: OperatorRepo.aggregate(Workflow, :count)
    }

    unless row_counts.tickets == 10000 and row_counts.organizations == 10 and
             row_counts.staff == 50,
           do: raise("incorrect fixture dimensions")

    :ok =
      :telemetry.attach(
        "read-benchmark",
        [:instantflow, :repo, :query],
        &__MODULE__.capture/4,
        nil
      )

    cold = rounds(clients, runtime, dimensions, 1)
    _warmup = rounds(clients, runtime, dimensions, 2)
    warm = rounds(clients, runtime, dimensions, dimensions.iterations)

    report = %{
      database: database,
      dimensions: dimensions,
      verified_row_counts: row_counts,
      source_revision: System.cmd("git", ["rev-parse", "HEAD"]) |> elem(0) |> String.trim(),
      environment: %{
        elixir: System.version(),
        otp: to_string(:erlang.system_info(:otp_release)),
        schedulers: :erlang.system_info(:schedulers_online),
        postgres: OperatorRepo.query!("SHOW server_version").rows,
        pool_size: 10
      },
      cold: summarize(cold),
      warm: summarize(warm),
      limits: %{
        backend_p95_ms: 500,
        per_read_incremental_memory_bytes: 33_554_432,
        fetched_payload_bytes: 4_194_304
      },
      limitations:
        "Backend supporting-volume checkpoint, not full T02 acceptance. Fresh application per invocation; PostgreSQL/OS caches are not flushed and fixture insertion warms them. Cold denotes each actor's first projection after fixture setup. Memory is observed caller-process heap at query boundaries, excluding pool processes/off-heap allocations. Fetched term bytes use Erlang external_size of returned row terms, not wire bytes. SQL bytes include the whole parameterized statement. Browser, complete policy-compilation time, full BEAM peak and actual wire bytes remain unmeasured. No serving database writes. Synthetic bulk fixture setup; reads use the actual runtime login and tenant authorization gates."
    }

    path = System.get_env("READ_REPORT", ".local/read-benchmark.json")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(report, pretty: true))

    IO.puts(
      Jason.encode!(
        Map.take(report, [:database, :dimensions, :verified_row_counts, :cold, :warm]),
        pretty: true
      )
    )

    IO.puts("Full report: #{path}")
    :telemetry.detach("read-benchmark")
    for pid <- [runtime, owner, control], do: Supervisor.stop(pid)
  end

  defp populate(index, hash, d) do
    org =
      OperatorRepo.insert!(%Organization{
        slug: "read-#{index}",
        name: "Synthetic read tenant #{index}"
      })

    dep = OperatorRepo.insert!(%Department{organization_id: org.id, name: "Readers"})
    hidden_dep = OperatorRepo.insert!(%Department{organization_id: org.id, name: "Hidden"})

    members =
      for n <- 1..5 do
        user =
          OperatorRepo.insert!(%User{
            email: "read#{index}-#{n}@example.invalid",
            name: "Synthetic reader",
            password_hash: hash
          })

        OperatorRepo.insert!(%Membership{
          organization_id: org.id,
          department_id: dep.id,
          user_id: user.id,
          role: "staff"
        })
      end

    [first | _] = members
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    processes =
      for i <- 1..d.processes do
        key = "read_process_#{i}"
        definition = definition(key, d.width)
        :ok = Definition.validate(definition)

        workflow =
          OperatorRepo.insert!(%Workflow{
            organization_id: org.id,
            key: key,
            name: definition["name"]
          })

        rows =
          for n <- 1..d.versions do
            %{
              organization_id: org.id,
              workflow_id: workflow.id,
              number: n,
              definition: put_in(definition, ["stages", Access.at(0), "label"], "Pinned #{n}"),
              bindings: %{
                "roles" => %{"requester" => ["external"], "reviewer" => ["staff"]},
                "departments" => %{"review_department" => dep.id}
              },
              published_by_id: first.user_id,
              inserted_at: now,
              updated_at: now
            }
          end

        {_, versions} = OperatorRepo.insert_all(Version, rows, returning: [:id, :number])
        {workflow, Enum.sort_by(versions, & &1.number)}
      end

    {workflow, versions} = hd(processes)

    count =
      case d.shape do
        "equal" -> 1000
        "uneven" when index == 1 -> 7000
        "uneven" when index <= 4 -> 334
        "uneven" -> 333
      end

    fields = definition("fixture", d.width)["sections"] |> hd() |> Map.fetch!("fields")
    values = Map.new(fields, &{&1["key"], String.duplicate("s", 1024)})

    rows =
      for n <- 1..count do
        %{
          organization_id: org.id,
          workflow_id: workflow.id,
          workflow_version_id: Enum.at(versions, rem(n - 1, d.used_versions)).id,
          requester_id: first.user_id,
          assigned_department_id:
            if(rem(n - 1, d.hidden + 1) == 0, do: dep.id, else: hidden_dep.id),
          stage: "draft",
          revision: 1,
          stage_revision: 1,
          inserted_at: now,
          updated_at: now
        }
      end

    tickets =
      rows
      |> Enum.chunk_every(500)
      |> Enum.flat_map(fn chunk ->
        {_, inserted} = OperatorRepo.insert_all(Ticket, chunk, returning: [:id])
        inserted
      end)

    for chunk <- Enum.chunk_every(tickets, 200) do
      OperatorRepo.insert_all(
        Section,
        Enum.map(
          chunk,
          &%{
            organization_id: org.id,
            ticket_id: &1.id,
            key: "request",
            values: values,
            revision: 1,
            inserted_at: now,
            updated_at: now
          }
        )
      )
    end

    expected = div(count + d.hidden, d.hidden + 1)

    Enum.map(members, fn member ->
      {Identity.scope(member.user_id, org.id), workflow.id, expected}
    end)
  end

  defp definition(key, width) do
    base = File.read!(Path.expand("design/examples/simple_approval.json")) |> Jason.decode!()

    fields = [
      %{"key" => "summary", "label" => "Summary", "type" => "long_text"},
      %{"key" => "justification", "label" => "Justification", "type" => "long_text"}
    ]

    fields =
      fields ++
        if width > 2,
          do:
            Enum.map(
              3..width,
              &%{"key" => "field_#{&1}", "label" => "Field #{&1}", "type" => "long_text"}
            ),
          else: []

    columns = fields |> Enum.take(width) |> Enum.map(&("request." <> &1["key"]))

    base
    |> Map.put("template_key", key)
    |> put_in(["sections", Access.at(0), "fields"], fields)
    |> Map.put("views", [
      %{"key" => "requests", "label" => "Requests", "type" => "table", "columns" => columns}
    ])
  end

  defp rounds(clients, runtime, d, n) do
    clients
    |> Task.async_stream(
      fn {actor, workflow, expected} ->
        Repo.put_dynamic_repo(runtime)
        Enum.map(1..n, fn _ -> measure(actor, workflow, expected, d.surface) end)
      end,
      max_concurrency: 50,
      timeout: :infinity,
      ordered: false
    )
    |> Enum.flat_map(fn {:ok, samples} -> samples end)
  end

  defp measure(actor, workflow, expected, surface) do
    :erlang.garbage_collect()
    {:memory, before_memory} = Process.info(self(), :memory)

    Process.put(:read_metrics, %{
      queries: 0,
      version_rows: 0,
      version_term_bytes: 0,
      fetched_rows: 0,
      fetched_term_bytes: 0,
      max_sql_bytes: 0,
      query_time_ms: 0.0,
      observed_peak_memory_bytes: before_memory
    })

    {us, result} =
      :timer.tc(fn ->
        case surface do
          "view" -> Views.search(actor, workflow, "requests")
          "search" -> Projections.search(actor, %{"workflow_id" => workflow})
          "options" -> Views.options(actor)
          "catalog" -> Workspaces.installed(actor)
        end
      end)

    if surface in ["view", "search"] and result.total != expected,
      do: raise("authorized count mismatch")

    metrics = Process.delete(:read_metrics)

    count =
      if surface == "view",
        do: length(result.rows),
        else: if(surface == "search", do: length(result.tickets), else: length(result))

    Map.merge(metrics, %{
      organization_id: actor.organization_id,
      backend_ms: us / 1000,
      returned_rows: count,
      observed_memory_growth_bytes: max(metrics.observed_peak_memory_bytes - before_memory, 0)
    })
  end

  @doc false
  def capture(_, measurements, metadata, _) do
    if metrics = Process.get(:read_metrics) do
      rows =
        case metadata.result do
          {:ok, %{rows: rows}} when is_list(rows) -> rows
          _ -> []
        end

      bytes = :erlang.external_size(rows)
      {:memory, memory} = Process.info(self(), :memory)
      version? = metadata[:source] == "workflow_versions"

      Process.put(:read_metrics, %{
        metrics
        | queries: metrics.queries + 1,
          version_rows: metrics.version_rows + if(version?, do: length(rows), else: 0),
          version_term_bytes: metrics.version_term_bytes + if(version?, do: bytes, else: 0),
          fetched_rows: metrics.fetched_rows + length(rows),
          fetched_term_bytes: metrics.fetched_term_bytes + bytes,
          max_sql_bytes: max(metrics.max_sql_bytes, byte_size(metadata.query)),
          query_time_ms:
            metrics.query_time_ms +
              System.convert_time_unit(measurements.total_time, :native, :microsecond) / 1000,
          observed_peak_memory_bytes: max(metrics.observed_peak_memory_bytes, memory)
      })
    end
  end

  defp summarize(samples) do
    per_tenant =
      samples
      |> Enum.group_by(& &1.organization_id)
      |> Map.new(fn {id, rows} -> {to_string(id), stats(rows)} end)

    %{
      requests: length(samples),
      overall: stats(samples),
      per_tenant: per_tenant,
      maximum_tenant_backend_p95_ms:
        per_tenant |> Map.values() |> Enum.map(& &1.backend_p95_ms) |> Enum.max()
    }
  end

  defp stats(rows) do
    %{
      backend_p95_ms: percentile(rows, :backend_ms),
      backend_max_ms: rows |> Enum.map(& &1.backend_ms) |> Enum.max(),
      query_time_p95_ms: percentile(rows, :query_time_ms),
      max_queries: max_metric(rows, :queries),
      max_version_rows: max_metric(rows, :version_rows),
      max_version_term_bytes: max_metric(rows, :version_term_bytes),
      max_sql_bytes: max_metric(rows, :max_sql_bytes),
      max_fetched_rows: max_metric(rows, :fetched_rows),
      max_fetched_term_bytes: max_metric(rows, :fetched_term_bytes),
      max_observed_memory_growth_bytes: max_metric(rows, :observed_memory_growth_bytes),
      max_returned_rows: max_metric(rows, :returned_rows)
    }
  end

  defp max_metric(rows, key), do: rows |> Enum.map(&Map.fetch!(&1, key)) |> Enum.max()

  defp percentile(rows, key),
    do:
      rows
      |> Enum.map(&Map.fetch!(&1, key))
      |> Enum.sort()
      |> Enum.at(max(ceil(length(rows) * 0.95) - 1, 0))

  defp number(key, default), do: System.get_env(key, to_string(default)) |> String.to_integer()
end

Instantflow.ReadBenchmark.run()
