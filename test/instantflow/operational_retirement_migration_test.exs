defmodule Instantflow.OperationalRetirementMigrationTest do
  use ExUnit.Case, async: false
  alias Instantflow.{Identity, Operations, OperatorRepo, Repo}
  alias Instantflow.Identity.{Organization, Department, User, Membership}
  alias Instantflow.Operations.{Resource, Product, Session, Batch, Line, Receipt, DayClose}
  alias Instantflow.WorkflowCatalog.{Workflow, Version, Templates, OperationalContract}
  alias Instantflow.WorkflowRuntime.{Ticket, Section}

  test "populated retirement and restore preserve unpaid amounts and release resources in the same process" do
    config = OperatorRepo.config() |> Keyword.take([:username, :password, :hostname, :port])

    control =
      start_supervised!(
        Supervisor.child_spec({Postgrex, config ++ [database: "postgres"]},
          id: :operational_retirement_control
        )
      )

    suffix = Integer.to_string(System.unique_integer([:positive]))
    source = "instantflow_operation_retire_" <> suffix
    restored = "instantflow_operation_restore_" <> suffix
    backup = Path.join(System.tmp_dir!(), source <> ".dump")
    Postgrex.query!(control, "CREATE DATABASE #{source} TEMPLATE template0 ENCODING 'UTF8'")
    previous_owner = OperatorRepo.get_dynamic_repo()
    previous_runtime = Repo.get_dynamic_repo()
    migrations = Application.app_dir(:instantflow, "priv/repo/migrations")

    try do
      owner = start_owner(source, :operational_retirement_owner)
      OperatorRepo.put_dynamic_repo(owner)
      Ecto.Migrator.run(OperatorRepo, migrations, :up, to: 20_261_022_100_818, log: false)
      f = populate(true, "archived_service")
      supported = populate(false, "supported_service")

      stable_tables =
        ~w(workflow_versions tickets ticket_sections catalog_products service_resources fulfillment_lines operation_receipts operation_day_closes budget_entries budget_holds command_receipts transition_events)

      before = snapshot(stable_tables)
      before_sessions = snapshot(~w(service_sessions))["service_sessions"]
      before_batches = snapshot(~w(fulfillment_batches))["fulfillment_batches"]
      Ecto.Migrator.run(OperatorRepo, migrations, :up, all: true, log: false)
      assert snapshot(stable_tables) == before

      for {table, rows, changed} <- [
            {"service_sessions", before_sessions, [f.open.id]},
            {"fulfillment_batches", before_batches, f.pending}
          ] do
        expected =
          Enum.map(rows, fn [row] ->
            [if(row["id"] in changed, do: Map.put(row, "status", "archived"), else: row)]
          end)

        assert snapshot([table])[table] == expected
      end

      assert OperatorRepo.get!(Session, f.open.id).settled_at == nil
      assert OperatorRepo.get!(Session, f.open.id).payment_method == nil
      assert OperatorRepo.get!(Session, f.settled.id).total == 2500
      assert OperatorRepo.get!(Session, supported.open.id).status == "open"

      audits =
        OperatorRepo.query!(
          "SELECT operation,count(*) FROM organization_events WHERE operation IN ('retired_session_archived','retired_batch_archived') GROUP BY operation"
        ).rows
        |> Map.new(fn [key, n] -> {key, n} end)

      assert audits == %{"retired_session_archived" => 1, "retired_batch_archived" => 2}

      for table <-
            ~w(service_sessions fulfillment_batches tickets retired_workflow_versions organization_events) do
        assert OperatorRepo.query!(
                 "SELECT relforcerowsecurity FROM pg_class WHERE relname='#{table}'"
               ).rows == [[true]]
      end

      # The populated snapshot includes every operational table plus pinned/audit data.
      tables = stable_tables ++ ~w(service_sessions fulfillment_batches organization_events)
      frozen = snapshot(tables)

      retired =
        OperatorRepo.query!(
          "SELECT row_to_json(r) FROM retired_workflow_versions r ORDER BY version_id"
        ).rows

      pg!("pg_dump", ["-Fc", "--no-owner", "-d", source, "-f", backup], config)
      Postgrex.query!(control, "CREATE DATABASE #{restored} TEMPLATE template0 ENCODING 'UTF8'")
      pg!("pg_restore", ["--exit-on-error", "--no-owner", "-d", restored, backup], config)
      restored_owner = start_owner(restored, :operational_restored_owner)
      OperatorRepo.put_dynamic_repo(restored_owner)
      assert snapshot(tables) == frozen

      assert OperatorRepo.query!(
               "SELECT row_to_json(r) FROM retired_workflow_versions r ORDER BY version_id"
             ).rows == retired

      runtime = start_runtime(restored)
      Repo.put_dynamic_repo(runtime)
      assert Repo.all(Session) == []
      actor = Identity.scope(f.user.id, f.organization.id)
      other = Identity.scope(supported.user.id, supported.organization.id)
      assert Operations.visit(other, f.open.id, f.workflow.id) == nil
      visit = Operations.visit(actor, f.open.id, f.workflow.id)
      assert visit.archived?
      assert visit.total == 1500
      assert Enum.count(visit.batches, &(&1.status == "archived")) == 2
      assert Enum.any?(visit.batches, &(&1.status == "handed"))
      assert Enum.any?(visit.batches, &(&1.status == "cancelled"))

      {:ok, draft} = Templates.clone(actor, f.version.id)

      definition =
        put_in(draft.definition, ["interface", "operations"], OperationalContract.defaults())

      {:ok, saved} = Templates.save(actor, draft.id, draft.revision, definition, draft.bindings)
      {:ok, replacement} = Templates.publish(actor, saved.id, saved.revision)
      assert replacement.workflow_id == f.workflow.id
      assert replacement.id != f.version.id
      assert {:error, :retired_version} = Operations.command(actor, f.opening)

      assert {:error, :retired_version} =
               operation(actor, f, "settle", %{
                 "session_id" => f.open.id,
                 "expected_total" => 1500,
                 "payment_method" => "pix"
               })

      assert {:error, :retired_version} =
               operation(actor, f, "handoff", %{"batch_id" => hd(f.pending)})

      workspace = Operations.workspace(actor, f.date, f.workflow.id)
      assert workspace.sessions == []
      assert workspace.report.archived_count == 1
      assert workspace.report.archived_total == 1500
      assert workspace.report.sales == 2500
      assert workspace.report.payments["pix"] == 2500
      assert workspace.report.open_total == 0
      assert workspace.report.cancellations == 200
      assert Enum.sum(Enum.map(workspace.report.consumption, & &1.quantity)) == 4

      assert {:ok, result} =
               Operations.command(actor, Map.put(f.opening, "key", "replacement-opening"))

      assert result["id"] != f.open.id

      assert {:error, :open_sessions} =
               operation(actor, f, "close_day", %{"business_date" => f.date})

      assert {:ok, _} =
               operation(actor, f, "settle", %{
                 "session_id" => result["id"],
                 "expected_total" => 0,
                 "payment_method" => "cash"
               })

      assert {:ok, _} = operation(actor, f, "close_day", %{"business_date" => f.date})
      closed = Operations.workspace(actor, f.date, f.workflow.id).report
      assert closed.sales == 2500
      assert closed.archived_total == 1500
      assert closed.closed.summary["archived_total"] == 1500
      assert closed.closed.summary["archived_count"] == 1

      assert {:error, :open_sessions} =
               operation(other, supported, "close_day", %{"business_date" => supported.date})

      assert {:error, :occupied} =
               Operations.command(other, Map.put(supported.opening, "key", "duplicate-open"))

      assert snapshot(
               stable_tables --
                 [
                   "workflow_versions",
                   "operation_receipts",
                   "operation_day_closes",
                   "tickets",
                   "ticket_sections",
                   "command_receipts",
                   "transition_events"
                 ]
             ) ==
               Map.take(
                 before,
                 ~w(catalog_products service_resources fulfillment_lines budget_entries budget_holds)
               )

      assert OperatorRepo.get!(Version, f.version.id).definition == f.version.definition
      assert OperatorRepo.get!(Receipt, f.receipt.id).result == f.receipt.result
      assert OperatorRepo.get!(DayClose, f.close.id).summary == f.close.summary
    after
      Repo.put_dynamic_repo(previous_runtime)
      OperatorRepo.put_dynamic_repo(previous_owner)

      for id <- [
            :operational_restored_runtime,
            :operational_restored_owner,
            :operational_retirement_owner
          ],
          do: stop_supervised(id)

      for database <- [restored, source],
          do: Postgrex.query!(control, "DROP DATABASE IF EXISTS #{database} WITH (FORCE)")

      File.rm(backup)
    end
  end

  defp populate(legacy?, key) do
    organization =
      OperatorRepo.insert!(%Organization{slug: String.replace(key, "_", "-"), name: key})

    department =
      OperatorRepo.insert!(%Department{organization_id: organization.id, name: "Service"})

    user =
      OperatorRepo.insert!(
        User.changeset(%User{email: key <> "@example.test"}, %{
          name: "Synthetic",
          password: "fictional-migration-only"
        })
      )

    OperatorRepo.insert!(%Membership{
      organization_id: organization.id,
      department_id: department.id,
      user_id: user.id,
      role: "admin"
    })

    workflow =
      OperatorRepo.insert!(%Workflow{organization_id: organization.id, key: key, name: key})

    definition =
      Instantflow.Examples.definition("resource_service") |> Map.put("template_key", key)

    definition =
      if legacy?,
        do: update_in(definition, ["interface"], &Map.delete(&1, "operations")),
        else: definition

    version =
      OperatorRepo.insert!(%Version{
        organization_id: organization.id,
        workflow_id: workflow.id,
        number: 1,
        definition: definition,
        bindings: %{
          "roles" => %{"operator" => ["admin"]},
          "departments" => %{"service_department" => department.id}
        },
        published_by_id: user.id
      })

    base = %{
      organization: organization,
      department: department,
      user: user,
      workflow: workflow,
      version: version
    }

    resource =
      OperatorRepo.insert!(%Resource{
        organization_id: organization.id,
        workflow_id: workflow.id,
        name: "Retained resource"
      })

    product =
      OperatorRepo.insert!(%Product{
        organization_id: organization.id,
        workflow_id: workflow.id,
        name: "Captured product",
        category: "Synthetic",
        price: 9900,
        destination: "Kitchen"
      })

    [[date]] = OperatorRepo.query!("SELECT (now() AT TIME ZONE 'America/Sao_Paulo')::date").rows
    settled = session(base, resource, date, "settled")
    batch(base, settled, product, "handed", 2500, 1)
    open = session(base, resource, date, "open")
    order = batch(base, open, product, "pending", 600, 2)
    batch(base, open, product, "handed", 300, 1)
    cancelled = batch(base, open, product, "cancelled", 200, 1)
    notice = batch(base, open, product, "pending", 200, 1, cancelled.id)

    opening = %{
      "workflow_id" => workflow.id,
      "operation" => "open_session",
      "key" => "historical-open",
      "resource_id" => resource.id,
      "responsible_actor" => "Captured actor",
      "business_date" => Date.to_iso8601(date)
    }

    receipt =
      OperatorRepo.insert!(%Receipt{
        organization_id: organization.id,
        workflow_id: workflow.id,
        actor_id: user.id,
        key: opening["key"],
        operation: "open_session",
        digest: :crypto.hash(:sha256, :erlang.term_to_binary(opening, [:deterministic])),
        result: %{"id" => open.id},
        inserted_at: now()
      })

    close =
      OperatorRepo.insert!(%DayClose{
        organization_id: organization.id,
        workflow_id: workflow.id,
        actor_id: user.id,
        business_date: Date.add(date, -1),
        summary: %{"sales" => 900, "payments" => %{"cash" => 900}},
        inserted_at: now()
      })

    Map.merge(base, %{
      open: open,
      settled: settled,
      pending: [order.id, notice.id],
      receipt: receipt,
      opening: opening,
      date: date,
      close: close
    })
  end

  defp session(f, resource, date, status) do
    ticket =
      OperatorRepo.insert!(%Ticket{
        organization_id: f.organization.id,
        workflow_id: f.workflow.id,
        workflow_version_id: f.version.id,
        requester_id: f.user.id,
        assigned_department_id: f.department.id,
        stage: if(status == "settled", do: "settled", else: "open")
      })

    for section <- f.version.definition["sections"],
        do:
          OperatorRepo.insert!(%Section{
            organization_id: f.organization.id,
            ticket_id: ticket.id,
            key: section["key"]
          })

    OperatorRepo.insert!(%Session{
      organization_id: f.organization.id,
      workflow_id: f.workflow.id,
      resource_id: resource.id,
      ticket_id: ticket.id,
      resource_name: resource.name,
      waiter: "Captured actor",
      business_date: date,
      status: status,
      total: if(status == "settled", do: 2500, else: 0),
      opened_at: now(),
      settled_at: if(status == "settled", do: now()),
      payment_method: if(status == "settled", do: "pix")
    })
  end

  defp batch(f, session, product, status, price, quantity, source \\ nil) do
    batch =
      OperatorRepo.insert!(%Batch{
        organization_id: f.organization.id,
        workflow_id: f.workflow.id,
        session_id: session.id,
        destination: "Captured kitchen",
        waiter: "Captured actor",
        status: status,
        kind: if(source, do: "cancellation", else: "order"),
        source_id: source,
        reason: if(source, do: "Historical cancellation"),
        print_count: 2,
        inserted_at: now()
      })

    OperatorRepo.insert!(%Line{
      organization_id: f.organization.id,
      workflow_id: f.workflow.id,
      batch_id: batch.id,
      product_id: product.id,
      name: "Historical product",
      unit_price: price,
      quantity: quantity,
      notes: "Captured note"
    })

    batch
  end

  defp operation(actor, f, name, attrs),
    do:
      Operations.command(
        actor,
        Map.merge(
          %{"workflow_id" => f.workflow.id, "operation" => name, "key" => Ecto.UUID.generate()},
          attrs
        )
      )

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp snapshot(tables),
    do:
      Map.new(
        tables,
        &{&1, OperatorRepo.query!("SELECT to_jsonb(t) FROM #{&1} t ORDER BY id").rows}
      )

  defp start_owner(database, name),
    do:
      start_supervised!(
        Supervisor.child_spec({OperatorRepo, [name: name, database: database, pool_size: 2]},
          id: name
        )
      )

  defp start_runtime(database),
    do:
      start_supervised!(
        Supervisor.child_spec(
          {Repo,
           [
             name: :operational_restored_runtime,
             database: database,
             username: "instantflow_runtime",
             password: System.get_env("RUNTIME_DB_PASSWORD", "instantflow-runtime-local-only"),
             pool: DBConnection.ConnectionPool,
             pool_size: 2
           ]},
          id: :operational_restored_runtime
        )
      )

  defp pg!(name, arguments, config) do
    bundled = Path.expand(".local/postgres/usr/lib/postgresql/16/bin/" <> name)
    executable = if File.regular?(bundled), do: bundled, else: System.find_executable(name)

    {output, status} =
      System.cmd(executable, arguments,
        stderr_to_stdout: true,
        env: [
          {"LD_LIBRARY_PATH",
           Path.expand(".local/postgres/usr/lib/x86_64-linux-gnu") <>
             ":" <> (System.get_env("LD_LIBRARY_PATH") || "")},
          {"PGHOST", config[:hostname]},
          {"PGPORT", to_string(config[:port])},
          {"PGUSER", config[:username]},
          {"PGPASSWORD", config[:password]}
        ]
      )

    assert status == 0, "#{name} failed: #{output}"
  end
end
