# Operator-only acceptance against a disposable synthetic database, never the live database.
Application.load(:instantflow)
Logger.configure(level: :warning)
database = System.fetch_env!("PYTHON_REHEARSAL_DATABASE")

unless Regex.match?(~r/^instantflow_s08_[a-f0-9]{12}$/, database),
  do: raise("invalid rehearsal database")

for variable <- ~w(DATABASE_URL OPERATOR_DATABASE_URL) do
  unless URI.parse(System.fetch_env!(variable)).path == "/" <> database,
    do: raise("rehearsal database mismatch")
end

endpoint = Application.get_env(:instantflow, InstantflowWeb.Endpoint)
Application.put_env(:instantflow, InstantflowWeb.Endpoint, Keyword.put(endpoint, :server, false))
Application.put_env(:instantflow, :calculation_worker, false)

IO.puts("rehearsal: migrate")

{:ok, _, _} =
  Ecto.Migrator.with_repo(Instantflow.OperatorRepo, &Ecto.Migrator.run(&1, :up, all: true))

IO.puts("rehearsal: start application")
{:ok, _} = Application.ensure_all_started(:instantflow)
IO.puts("rehearsal: start operator")
{:ok, _} = Instantflow.OperatorRepo.start_link()

defmodule Instantflow.PythonRehearsal do
  import Ecto.Query

  alias Instantflow.{
    Access,
    Calculations,
    Identity,
    Repo,
    Tenant,
    WorkflowCatalog,
    WorkflowRuntime
  }

  alias Instantflow.Calculations.{Catalogue, Demo, Run, Runner}

  def main do
    IO.puts("rehearsal: switch")
    :ok = Instantflow.Release.python_switch(true)
    IO.puts("rehearsal: setup")
    a = setup("alpha")
    b = setup("beta")
    ta = ticket(a)
    tb = ticket(b)
    {:error, :calculation_required} = transition(a.actor, ta, "review")
    {:error, _} = Catalogue.source(b.actor, a.script.id)

    {:ok, []} =
      Tenant.raw(b.actor.organization_id, fn ->
        Repo.all(from r in Run, where: r.ticket_id == ^ta)
      end)

    {:ok, supervisor} =
      Supervisor.start_child(
        Instantflow.Supervisor,
        {Task.Supervisor, name: Instantflow.Calculations.Tasks}
      )

    parent = self()

    old_worker =
      Task.Supervisor.async_nolink(supervisor, fn ->
        {:ok, {run, script}} = Calculations.claim(a.actor.organization_id)
        send(parent, {:claimed, run, script})

        receive do
          :finish -> :ok
        end
      end)

    {old, script} =
      receive do
        {:claimed, run, script} -> {run, script}
      after
        5000 -> raise("claim deadline")
      end

    Process.exit(old_worker.pid, :kill)

    receive do
      {:DOWN, ref, :process, pid, :killed} when ref == old_worker.ref and pid == old_worker.pid ->
        :ok
    after
      5000 -> raise("worker death not observed")
    end

    request = Runner.request(script, old.snapshot, old.id, old.fence)

    {:error, :not_found} =
      Calculations.finalize(
        b.actor.organization_id,
        old.id,
        old.fence,
        request,
        {:error, :runner_unavailable}
      )

    started = System.monotonic_time(:millisecond)

    {:ok, _} =
      Supervisor.start_child(Instantflow.Supervisor, {Instantflow.Calculations.Worker, []})

    rb = await(b.actor, tb, "succeeded", 8000)
    other_ms = System.monotonic_time(:millisecond) - started
    if other_ms >= 8000, do: raise("other tenant stalled")
    ra = await(a.actor, ta, "succeeded", 30_000)
    recovery_ms = System.monotonic_time(:millisecond) - started

    unless ra.id == old.id and ra.fence != old.fence and ra.attempts == 2 and rb.attempts == 1,
      do: raise("lease recovery mismatch")

    response = Runner.execute(request)
    {:ok, %{"status" => "succeeded"}} = response

    {:error, :stale_attempt} =
      Calculations.finalize(a.actor.organization_id, old.id, old.fence, request, response)

    for {fixture, id} <- [{a, ta}, {b, tb}] do
      {:ok, data} = WorkflowRuntime.get(fixture.actor, id)
      quote = Enum.find(data.sections, &(&1.key == "quotation"))

      unless quote.values == hd(Demo.attributes("")["fixtures"])["output"] and
               "quotation" not in data.editable,
             do: raise("quotation mismatch")

      {:ok, _} = transition(fixture.actor, id, "review")
    end

    :sys.suspend(Instantflow.Calculations.Worker)
    stale_ticket = ticket(a)
    :ok = Instantflow.Release.python_switch(false)
    :ok = Instantflow.Release.python_switch(true)
    :sys.resume(Instantflow.Calculations.Worker)
    await(a.actor, stale_ticket, "stale", 5000)
    {:error, :calculation_required} = transition(a.actor, stale_ticket, "review")
    :ok = Instantflow.Release.python_switch(false)

    IO.puts(
      "INSTANTFLOW_PYTHON_REHEARSAL=" <>
        Jason.encode!(%{
          date: DateTime.utc_now(),
          database: "disposable synthetic database; removed after rehearsal",
          broker: "real authenticated Unix socket; real ARM64 gVisor",
          tests: [
            %{name: "two_organizations_field_trip_402000_cents", passed: true},
            %{name: "required_result_and_readonly_output", passed: true},
            %{name: "wrong_tenant_source_run_and_finalization_denied", passed: true},
            %{
              name: "other_tenant_progress_after_worker_death",
              passed: true,
              milliseconds: other_ms
            },
            %{
              name: "real_lease_expiry_new_fence_same_run",
              passed: true,
              milliseconds: recovery_ms,
              attempts: ra.attempts
            },
            %{name: "late_real_reply_rejected", passed: true},
            %{name: "durable_disable_reenable_fences_old_generation", passed: true}
          ]
        })
    )
  end

  defp setup(slug) do
    {:ok, provisioned} =
      Instantflow.Organizations.Operator.provision(
        "sprint08-rehearsal",
        slug,
        "Organização fictícia " <> slug,
        slug <> "@synthetic.invalid",
        slug
      )

    {:ok, user} =
      Identity.accept_invitation(provisioned.token, %{
        "name" => "Pessoa fictícia",
        "password" => Base.encode64(:crypto.strong_rand_bytes(32))
      })

    actor = Identity.scope(user.id, provisioned.organization.id)

    for role <- ~w(python_author python_reviewer python_binder python_execute python_source),
        do: {:ok, _} = Access.grant(actor, actor.id, actor.department_id, role)

    runtime = System.fetch_env!("PYTHON_IMAGE") |> String.split(":") |> List.last()
    {:ok, script} = Catalogue.register(actor, Demo.attributes(runtime))
    {:ok, :verified} = Catalogue.verify(actor, script.id)
    {:ok, :ok} = Catalogue.activate(actor, script.id, true)

    bindings = %{
      "roles" => %{"requester" => ["admin"], "reviewer" => ["admin"]},
      "departments" => %{"responsible" => actor.department_id}
    }

    {:ok, version} =
      WorkflowCatalog.publish(actor, Demo.definition(script.key, script.digest), bindings)

    %{actor: actor, version: version, script: script}
  end

  defp ticket(f) do
    {:ok, created} =
      WorkflowRuntime.command(f.actor, %{
        "operation" => "create",
        "workflow_id" => f.version.workflow_id,
        "key" => Ecto.UUID.generate()
      })

    id = created["ticket_id"]
    {:ok, data} = WorkflowRuntime.get(f.actor, id)
    section = Enum.find(data.sections, &(&1.key == "request"))

    {:ok, _} =
      WorkflowRuntime.command(f.actor, %{
        "operation" => "save_section",
        "key" => Ecto.UUID.generate(),
        "ticket_id" => id,
        "section" => "request",
        "values" => hd(Demo.attributes("")["fixtures"])["input"],
        "expected_stage_revision" => data.ticket.stage_revision,
        "expected_section_revision" => section.revision
      })

    {:ok, _} = transition(f.actor, id, "calculate")

    Phoenix.PubSub.subscribe(
      Instantflow.PubSub,
      Instantflow.Delivery.topic(f.actor.organization_id, id)
    )

    id
  end

  defp transition(actor, id, edge) do
    {:ok, data} = WorkflowRuntime.get(actor, id)

    WorkflowRuntime.command(actor, %{
      "operation" => "transition",
      "key" => Ecto.UUID.generate(),
      "ticket_id" => id,
      "transition" => edge,
      "expected_revision" => data.ticket.revision,
      "section_revisions" => Map.new(data.sections, &{&1.key, &1.revision})
    })
  end

  defp await(actor, id, status, timeout),
    do: wait(actor, id, status, System.monotonic_time(:millisecond) + timeout)

  defp wait(actor, id, expected, deadline) do
    {:ok, run} =
      Tenant.raw(actor.organization_id, fn ->
        Repo.one!(from r in Run, where: r.ticket_id == ^id, order_by: [desc: r.id], limit: 1)
      end)

    cond do
      run.status == expected ->
        run

      System.monotonic_time(:millisecond) >= deadline ->
        raise("run deadline: " <> run.status)

      run.status in ["failed", "timed_out", "cancelled"] ->
        raise("unexpected terminal status: " <> run.status)

      true ->
        receive do
          _ -> :ok
        after
          250 -> :ok
        end

        wait(actor, id, expected, deadline)
    end
  end
end

Instantflow.PythonRehearsal.main()
