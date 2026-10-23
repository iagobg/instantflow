defmodule Instantflow.Benchmark do
  @moduledoc false
  alias Instantflow.{
    Access,
    Delivery,
    Finance,
    Identity,
    OperatorRepo,
    Repo,
    WorkflowRuntime
  }

  alias Instantflow.Identity.{Department, Membership, Organization, User}
  alias Instantflow.WorkflowRuntime.{Section, Ticket}

  def run do
    Application.put_env(:instantflow, :delivery_worker, false)
    Application.put_env(:instantflow, :calculation_worker, false)
    Application.put_env(:instantflow, :calculation_execution, false)
    {:ok, _} = Application.ensure_all_started(:instantflow)
    config = OperatorRepo.config() |> Keyword.take([:username, :password, :hostname, :port])
    {:ok, control} = Postgrex.start_link(config ++ [database: "postgres"])

    database =
      "instantflow_benchmark_" <> Base.encode16(:crypto.strong_rand_bytes(5), case: :lower)

    Postgrex.query!(control, "CREATE DATABASE #{database} TEMPLATE template0 ENCODING 'UTF8'")

    {:ok, owner} =
      OperatorRepo.start_link(name: :benchmark_operator, database: database, pool_size: 2)

    OperatorRepo.put_dynamic_repo(owner)

    Ecto.Migrator.run(
      OperatorRepo,
      Application.app_dir(:instantflow, "priv/repo/migrations"),
      :up,
      all: true,
      log: false
    )

    runtime_pool = String.to_integer(System.get_env("BENCHMARK_POOL_SIZE", "10"))

    {:ok, runtime} =
      Repo.start_link(
        name: :benchmark_runtime,
        database: database,
        username: "instantflow_runtime",
        password: System.get_env("RUNTIME_DB_PASSWORD", "instantflow-runtime-local-only"),
        pool: DBConnection.ConnectionPool,
        pool_size: runtime_pool,
        queue_target: 1000,
        queue_interval: 1000
      )

    Repo.put_dynamic_repo(runtime)

    password_hash =
      User.changeset(%User{email: "synthetic@example.com"}, %{
        name: "Synthetic",
        password: "benchmark-fictional-only"
      })
      |> Ecto.Changeset.get_change(:password_hash)

    clients = Enum.flat_map(1..10, &school(&1, password_hash))

    interval =
      String.to_integer(
        System.get_env(
          "BENCHMARK_POLL_MS",
          to_string(Application.get_env(:instantflow, :delivery_poll_interval_ms, 250))
        )
      )

    worker =
      spawn_link(fn ->
        Repo.put_dynamic_repo(runtime)
        poll(interval)
      end)

    started = System.monotonic_time(:millisecond)
    iterations = String.to_integer(System.get_env("BENCHMARK_ITERATIONS", "10"))

    uneven? = System.get_env("BENCHMARK_UNEVEN", "false") == "true"
    busy_organization = elem(hd(clients), 0).organization_id

    mixed? = System.get_env("BENCHMARK_MIXED", "false") == "true"

    actors_by_org =
      clients
      |> Enum.group_by(fn {actor, _} -> actor.organization_id end)
      |> Map.new(fn {org, list} -> {org, Enum.map(list, &elem(&1, 0))} end)

    results =
      Task.async_stream(
        clients,
        fn {actor, ids} ->
          Repo.put_dynamic_repo(runtime)

          count =
            if uneven? and actor.organization_id == busy_organization,
              do: iterations * 4,
              else: iterations

          Enum.flat_map(1..count, fn n ->
            id = Enum.fetch!(ids, n - 1)
            topic = Delivery.topic(actor.organization_id, id)
            Phoenix.PubSub.subscribe(Instantflow.PubSub, topic)
            {search_us, search} = :timer.tc(fn -> WorkflowRuntime.search(actor) end)
            unless search.total > 0, do: raise("authorized list empty")
            flush()

            steps =
              lifecycle(actor, id, n, Map.fetch!(actors_by_org, actor.organization_id), mixed?)

            last = List.last(steps)
            committed_at = System.monotonic_time(:millisecond)

            visible =
              await_visible(
                actor,
                id,
                last.result["revision"],
                committed_at,
                committed_at + 15000
              )

            Phoenix.PubSub.unsubscribe(Instantflow.PubSub, topic)

            Enum.map(
              steps,
              &Map.merge(Map.drop(&1, [:result]), %{
                organization_id: actor.organization_id,
                search_ms: search_us / 1000,
                visibility_ms: visible
              })
            )
          end)
        end,
        max_concurrency: 50,
        timeout: :infinity,
        ordered: false
      )
      |> Enum.flat_map(fn {:ok, samples} -> samples end)

    send(worker, {:stop, self()})

    receive do
      :stopped -> :ok
    after
      15000 -> raise("poll worker did not stop")
    end

    elapsed = System.monotonic_time(:millisecond) - started

    per_organization =
      results
      |> Enum.group_by(& &1.organization_id)
      |> Map.new(fn {id, samples} -> {to_string(id), summary(samples)} end)

    row_counts = %{
      tickets: OperatorRepo.aggregate(Ticket, :count),
      organizations: OperatorRepo.aggregate(Organization, :count),
      staff: length(clients)
    }

    unless row_counts == %{tickets: 10_000, organizations: 10, staff: 50},
      do: raise("load fixture dimensions differ")

    report = %{
      verified_row_counts: row_counts,
      database: database,
      records: 10_000,
      organizations: 10,
      concurrent_staff: 50,
      samples: length(results),
      command_mix:
        if(mixed?,
          do:
            "proposal saves, submission, academic approval, finance reservation, order, posting, receiving and completion",
          else: "proposal saves"
        ),
      load_shape:
        if(uneven?,
          do: "School 1 performs four times as many updates per staff member",
          else: "Equal iterations per school"
        ),
      elapsed_ms: elapsed,
      poll_interval_ms: interval,
      dataset:
        "Per school: 700 requisitions, 100 trips, 100 enrollments, 100 incidents; 5 local actors. Synthetic bulk fixture stages; runtime writes use guarded commands.",
      environment: %{
        otp: to_string(:erlang.system_info(:otp_release)),
        elixir: System.version(),
        schedulers: :erlang.system_info(:schedulers_online),
        os: inspect(:os.type()),
        cpu: File.read!("/proc/cpuinfo") |> String.split("
") |> Enum.find(&String.starts_with?(&1, "model name")),
        memory: File.read!("/proc/meminfo") |> String.split("
") |> hd(),
        postgres: Repo.query!("SHOW server_version").rows |> hd() |> hd(),
        runtime_pool: runtime_pool
      },
      totals: summary(results),
      per_organization: per_organization,
      thresholds: %{command_p95_ms: 500, committed_visibility_p95_ms: 1000},
      accepted_command_target:
        Enum.all?(per_organization, fn {_, stats} ->
          stats.command_p95_ms <= 500 and
            Enum.all?(stats.operations, fn {_, operation} -> operation.p95_ms <= 500 end)
        end),
      visibility_target:
        Enum.all?(per_organization, fn {_, stats} -> stats.visibility_p95_ms <= 1000 end),
      limitations:
        "Local WSL backend and PubSub/requery benchmark. Includes pool wait. Excludes browser rendering/network, real providers and production-host certification. Generated database retained; no serving database altered."
    }

    path = System.get_env("BENCHMARK_REPORT", ".local/benchmark.json")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(report, pretty: true))

    IO.puts(
      Jason.encode!(
        Map.take(report, [
          :database,
          :samples,
          :elapsed_ms,
          :totals,
          :accepted_command_target,
          :visibility_target
        ]),
        pretty: true
      )
    )

    IO.puts("Full report: #{path}")

    if System.get_env("BENCHMARK_ENFORCE", "false") == "true" and
         not (report.accepted_command_target and report.visibility_target),
       do: raise("measured performance target failed")

    Supervisor.stop(runtime)
    Supervisor.stop(owner)
    GenServer.stop(control)
  end

  defp school(index, hash) do
    org =
      OperatorRepo.insert!(%Organization{slug: "load-#{index}", name: "Escola fictícia #{index}"})

    dep =
      OperatorRepo.insert!(%Department{organization_id: org.id, name: "Departamento fictício"})

    members =
      for i <- 1..5 do
        user =
          OperatorRepo.insert!(%User{
            email: "load#{index}-#{i}@example.invalid",
            name: "Pessoa fictícia #{i}",
            password_hash: hash
          })

        OperatorRepo.insert!(%Membership{
          organization_id: org.id,
          department_id: dep.id,
          user_id: user.id,
          role: if(i == 1, do: "admin", else: "staff")
        })
      end

    admin = Identity.scope(hd(members).user_id, org.id)

    for member <- members,
        role <-
          ~w(teacher head finance finance_allocator finance_reverser operations dean counselor admissions it) do
      {:ok, _} = Access.grant(admin, member.id, dep.id, role)
    end

    actors = Enum.map(members, &Identity.scope(&1.user_id, org.id))
    {:ok, account} = Finance.create_account(admin, dep.id, "Orçamento fictício")

    {:ok, _} =
      Finance.allocate(hd(actors), account.id, 1_000_000_000, "Carga sintética", "initial")

    deps = Map.new(~w(head finance operations safety), &{&1 <> "_department", dep.id})
    {:ok, req} = Finance.install(admin, "requisition", deps, account.id)
    {:ok, trip} = Finance.install(admin, "field_trip", deps, account.id)

    {:ok, enrollment} =
      Instantflow.Examples.install(admin, "enrollment", %{
        "roles" => %{
          "guardian" => ["external"],
          "admissions" => ["admin", "admissions"],
          "academic" => ["head"],
          "finance" => ["finance"],
          "it" => ["it"]
        },
        "departments" =>
          Map.new(~w(admissions academic finance it), &{&1 <> "_department", dep.id})
      })

    {:ok, incident} =
      Instantflow.Examples.install(admin, "incident", %{
        "roles" => %{"teacher" => ["teacher"], "dean" => ["dean"], "counselor" => ["counselor"]},
        "departments" => %{"dean_department" => dep.id, "support_department" => dep.id}
      })

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    requests =
      for {version, count} <- [{req, 700}, {trip, 100}, {enrollment, 100}, {incident, 100}],
          reduce: [] do
        acc ->
          rows =
            for n <- 1..count do
              actor = Enum.at(actors, rem(n, 5))

              %{
                organization_id: org.id,
                workflow_id: version.workflow_id,
                workflow_version_id: version.id,
                requester_id: actor.user_id,
                assigned_department_id: dep.id,
                stage: "draft",
                revision: 1,
                stage_revision: 1,
                inserted_at: now,
                updated_at: now
              }
            end

          {_, inserted} = OperatorRepo.insert_all(Ticket, rows, returning: [:id, :requester_id])

          sections =
            for row <- inserted, section <- version.definition["sections"] do
              %{
                organization_id: org.id,
                ticket_id: row.id,
                key: section["key"],
                values: values(version.definition["template_key"], section["key"]),
                revision: 1,
                inserted_at: now,
                updated_at: now
              }
            end

          OperatorRepo.insert_all(Section, sections)
          if version.id == req.id, do: inserted, else: acc
      end

    Enum.map(actors, fn actor ->
      {actor, requests |> Enum.filter(&(&1.requester_id == actor.user_id)) |> Enum.map(& &1.id)}
    end)
  end

  defp lifecycle(actor, id, n, actors, mixed?) do
    {:ok, data} = WorkflowRuntime.get(actor, id)
    section = Enum.find(data.sections, &(&1.key == "request"))

    first =
      save(
        actor,
        id,
        "request",
        Map.put(section.values, "summary", "Amostra fictícia #{n}"),
        "save_proposal"
      )

    if mixed? do
      index = Enum.find_index(actors, &(&1.id == actor.id))
      head = Enum.at(actors, rem(index + 1, 5))
      finance = Enum.at(actors, rem(index + 2, 5))
      operations = Enum.at(actors, rem(index + 3, 5))

      [
        first,
        transition(actor, id, "submit"),
        transition(head, id, "academic_approve"),
        transition(finance, id, "reserve"),
        save(operations, id, "order", %{"reference" => "Pedido simulado"}, "save_order"),
        transition(operations, id, "order"),
        save(operations, id, "delivery", %{"received" => 4}, "receive"),
        transition(operations, id, "finish")
      ]
    else
      [first]
    end
  end

  defp save(actor, id, key, values, label) do
    {:ok, data} = WorkflowRuntime.get(actor, id)
    section = Enum.find(data.sections, &(&1.key == key))

    perform(
      actor,
      %{
        "operation" => "save_section",
        "key" => Ecto.UUID.generate(),
        "ticket_id" => id,
        "section" => key,
        "values" => values,
        "expected_stage_revision" => data.ticket.stage_revision,
        "expected_section_revision" => section.revision
      },
      label
    )
  end

  defp transition(actor, id, key) do
    {:ok, data} = WorkflowRuntime.get(actor, id)

    perform(
      actor,
      %{
        "operation" => "transition",
        "key" => Ecto.UUID.generate(),
        "ticket_id" => id,
        "transition" => key,
        "expected_revision" => data.ticket.revision,
        "section_revisions" => Map.new(data.sections, &{&1.key, &1.revision}),
        "reason" => nil
      },
      key
    )
  end

  defp perform(actor, command, label) do
    {us, {:ok, result}} = :timer.tc(fn -> WorkflowRuntime.command(actor, command) end)
    %{operation: label, command_ms: us / 1000, result: result}
  end

  defp values(_, "request"),
    do: %{
      "summary" => "Carga fictícia",
      "justification" => "Medição sintética",
      "quantity" => 4,
      "amount" => 6000
    }

  defp values("enrollment", "application"),
    do: %{
      "student_name" => "Estudante fictício",
      "guardian_name" => "Contato fictício",
      "school_year" => "2027"
    }

  defp values("incident", "report"),
    do: %{
      "facts" => "Relato fictício",
      "students" => "Estudante fictício",
      "location" => "Pátio",
      "occurred_at" => "2026-10-21T12:00:00Z",
      "urgency" => "Rotina"
    }

  defp values(_, _), do: %{}

  defp flush do
    receive do
      {:ticket_changed, _, _} -> flush()
    after
      0 -> :ok
    end
  end

  defp await_visible(actor, id, revision, start, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:ticket_changed, _, ^id} ->
        case WorkflowRuntime.get(actor, id) do
          {:ok, %{ticket: %{revision: actual}}} when actual >= revision ->
            System.monotonic_time(:millisecond) - start

          _ ->
            await_visible(actor, id, revision, start, deadline)
        end
    after
      remaining -> raise("committed visibility exceeded 15 seconds")
    end
  end

  defp poll(interval) do
    receive do
      {:stop, from} -> send(from, :stopped)
    after
      interval ->
        Delivery.drain()
        poll(interval)
    end
  end

  defp summary(samples) do
    %{
      command_p50_ms: percentile(samples, :command_ms, 0.5),
      command_p95_ms: percentile(samples, :command_ms, 0.95),
      search_p95_ms: percentile(samples, :search_ms, 0.95),
      visibility_p95_ms: percentile(samples, :visibility_ms, 0.95),
      operations:
        samples
        |> Enum.group_by(& &1.operation)
        |> Map.new(fn {key, items} ->
          {key, %{count: length(items), p95_ms: percentile(items, :command_ms, 0.95)}}
        end)
    }
  end

  defp percentile(samples, key, quantile),
    do:
      samples
      |> Enum.map(&Map.fetch!(&1, key))
      |> Enum.sort()
      |> Enum.at(max(ceil(length(samples) * quantile) - 1, 0))
end

Instantflow.Benchmark.run()
