defmodule Instantflow.Sprint11SupportedRecoveryTest do
  use ExUnit.Case, async: false

  alias Instantflow.{
    Access,
    BuilderFixtures,
    Delivery,
    Finance,
    FinanceFixtures,
    Identity,
    Operations,
    OperatorRepo,
    Participants,
    PrivateDocuments,
    Repo,
    Sprint11AcceptanceFixtures,
    WorkflowFixtures,
    WorkflowRuntime
  }

  alias Instantflow.Identity.{Organization, Department, Membership, User}

  test "empty supported builder population survives migration, backup and runtime recovery" do
    config = OperatorRepo.config() |> Keyword.take([:username, :password, :hostname, :port])

    control =
      start_supervised!(
        Supervisor.child_spec({Postgrex, config ++ [database: "postgres"]},
          id: :s11_recovery_control
        )
      )

    suffix = Integer.to_string(System.unique_integer([:positive]))
    source = "instantflow_s11_source_" <> suffix
    restored = "instantflow_s11_restored_" <> suffix
    backup = Path.join(System.tmp_dir!(), source <> ".dump")
    Postgrex.query!(control, "CREATE DATABASE #{source} TEMPLATE template0 ENCODING 'UTF8'")
    previous_owner = OperatorRepo.get_dynamic_repo()
    previous_runtime = Repo.get_dynamic_repo()

    try do
      owner = repo(OperatorRepo, source, :s11_source_owner)
      OperatorRepo.put_dynamic_repo(owner)
      migrations = Application.app_dir(:instantflow, "priv/repo/migrations")
      Ecto.Migrator.run(OperatorRepo, migrations, :up, all: true, log: false)
      runtime = repo(Repo, source, :s11_source_runtime)
      Repo.put_dynamic_repo(runtime)
      first = populate("first")
      other = populate("second")

      tables =
        OperatorRepo.query!(
          "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename"
        ).rows
        |> List.flatten()

      frozen = snapshot(tables)
      assert Ecto.Migrator.run(OperatorRepo, migrations, :up, all: true, log: false) == []
      assert snapshot(tables) == frozen
      assert length(frozen["workflow_versions"]) == 12
      assert length(frozen["private_documents"]) == 2
      assert length(frozen["ticket_participants"]) == 2
      assert length(frozen["budget_holds"]) == 2
      assert length(frozen["fulfillment_lines"]) == 4
      assert length(frozen["outbox_messages"]) >= 2

      assert OperatorRepo.query!("SELECT count(*) FROM outbox_messages WHERE payload ? 'release'").rows ==
               [[2]]

      pg!("pg_dump", ["-Fc", "--no-owner", "-d", source, "-f", backup], config)
      Postgrex.query!(control, "CREATE DATABASE #{restored} TEMPLATE template0 ENCODING 'UTF8'")
      pg!("pg_restore", ["--exit-on-error", "--no-owner", "-d", restored, backup], config)
      OperatorRepo.put_dynamic_repo(repo(OperatorRepo, restored, :s11_restore_owner))
      assert snapshot(tables) == frozen
      Repo.put_dynamic_repo(repo(Repo, restored, :s11_restore_runtime))
      assert Repo.all(Instantflow.WorkflowRuntime.Ticket) == []

      for f <- [first, other] do
        assert {:ok, recovered} = WorkflowRuntime.get(f.admin, f.ticket)
        assert recovered.ticket.workflow_version_id == f.equipment.id
        assert {:ok, file} = PrivateDocuments.download(f.customer, f.document.object_key)
        assert file.content == Instantflow.EnrollmentFixtures.pdf()
        assert {:ok, replay} = Operations.command(f.admin, f.open_command)
        assert replay["id"] == f.session

        assert Operations.workspace(f.admin, f.date, f.restaurant.workflow_id).report.sales ==
                 1500

        assert {:ok, %{status: "failed"}} =
                 Delivery.process(f.admin.organization_id, f.message.id)

        assert {:ok, _} = Delivery.Curated.retry(f.admin, f.message.id)

        assert {:ok, %{status: "succeeded"}} =
                 Delivery.process(f.admin.organization_id, f.message.id)

        assert [%{content: [_]}] =
                 Delivery.Curated.inbox(f.customer, f.equipment.workflow_id).rows

        assert {:ok, _} =
                 Participants.command(f.admin, participant(f.ticket, f.customer.id, "revoke", 2))

        assert {:error, :not_found} = PrivateDocuments.download(f.customer, f.document.object_key)
        assert Delivery.Curated.inbox(f.customer, f.equipment.workflow_id).rows == []
      end

      assert {:error, :not_found} = WorkflowRuntime.get(other.admin, first.ticket)

      assert {:error, :not_found} =
               PrivateDocuments.download(other.customer, first.document.object_key)

      assert Operations.visit(first.admin, first.session, first.equipment.workflow_id) == nil
      assert Operations.visit(other.admin, first.session, first.restaurant.workflow_id) == nil

      File.write!(
        Path.expand(".local/sprint11-supported-recovery.json"),
        Jason.encode!(
          %{
            tables: length(tables),
            row_counts: Map.new(frozen, fn {k, v} -> {k, length(v)} end),
            snapshot_sha256:
              :crypto.hash(:sha256, :erlang.term_to_binary(frozen, [:deterministic]))
              |> Base.encode16(case: :lower),
            organizations: 2,
            processes: 12,
            exact_restore: true,
            runtime_rls: true,
            private_bytes: true,
            pending_jobs:
              "retained supported curated jobs; fail-once and authorized retry verified after restore",
            legacy_jobs: "separate guardian migration test verifies cancellation with audit"
          },
          pretty: true
        )
      )
    after
      Repo.put_dynamic_repo(previous_runtime)
      OperatorRepo.put_dynamic_repo(previous_owner)

      for id <- [:s11_source_runtime, :s11_source_owner, :s11_restore_runtime, :s11_restore_owner],
          do: stop_supervised(id)

      for db <- [restored, source],
          do: Postgrex.query!(control, "DROP DATABASE IF EXISTS #{db} WITH (FORCE)")

      File.rm(backup)
    end
  end

  defp populate(slug) do
    org = OperatorRepo.insert!(%Organization{slug: slug, name: "Synthetic " <> slug})
    dep = OperatorRepo.insert!(%Department{organization_id: org.id, name: "Local team"})

    user =
      OperatorRepo.insert!(
        User.changeset(%User{email: slug <> "@example.invalid"}, %{
          name: "Synthetic admin",
          password: "fictional-recovery-only"
        })
      )

    OperatorRepo.insert!(%Membership{
      organization_id: org.id,
      department_id: dep.id,
      user_id: user.id,
      role: "admin"
    })

    worker =
      OperatorRepo.insert!(
        User.changeset(%User{email: slug <> "-worker@example.invalid"}, %{
          name: "Synthetic requester",
          password: "fictional-recovery-only"
        })
      )

    OperatorRepo.insert!(%Membership{
      organization_id: org.id,
      department_id: dep.id,
      user_id: worker.id,
      role: "staff"
    })

    admin = Identity.scope(user.id, org.id)
    requester = Identity.scope(worker.id, org.id)
    for role <- ~w(finance finance_allocator), do: Access.grant(admin, admin.id, dep.id, role)
    {:ok, account} = Finance.create_account(admin, dep.id, "Recovery account")

    {:ok, _} =
      Finance.allocate(admin, account.id, 10_000, "Synthetic allocation", Ecto.UUID.generate())

    versions =
      Enum.map(Sprint11AcceptanceFixtures.definitions(), fn d ->
        bindings = Sprint11AcceptanceFixtures.bindings(admin, d, account.id, "admin")

        bindings =
          if d["template_key"] in ~w(independent_requisition independent_field_trip),
            do: put_in(bindings, ["roles", "copy_requester"], ["staff"]),
            else: bindings

        BuilderFixtures.install(admin, d, bindings)
      end)

    requisition =
      Enum.find(versions, &(&1.definition["template_key"] == "independent_requisition"))

    {:ok, created} =
      WorkflowRuntime.command(requester, %{
        "operation" => "create",
        "workflow_id" => requisition.workflow_id,
        "key" => Ecto.UUID.generate()
      })

    id = created["ticket_id"]

    {:ok, _} =
      FinanceFixtures.save(requester, id, "copy_request", %{
        "copy_summary" => "Recovery request",
        "copy_justification" => "Synthetic",
        "copy_quantity" => 2,
        "copy_amount" => 2000
      })

    {:ok, _} = WorkflowFixtures.transition(requester, id, "copy_submit")
    {:ok, _} = WorkflowFixtures.transition(admin, id, "copy_academic_approve")
    {:ok, _} = WorkflowFixtures.transition(admin, id, "copy_reserve")
    equipment = Enum.find(versions, &(&1.definition["template_key"] == "equipment_external_desk"))
    restaurant = Enum.find(versions, &(&1.definition["template_key"] == "supper_room"))
    customer = BuilderFixtures.invite_external(admin, slug <> "-external@example.invalid")

    {:ok, station} = operation(admin, equipment, "add_resource", %{"name" => "Recovery bench"})

    {:ok, opened_equipment} =
      operation(admin, equipment, "open_session", %{
        "resource_id" => station["id"],
        "responsible_actor" => "Synthetic technician",
        "business_date" => Date.to_iso8601(Operations.today(admin))
      })

    ticket =
      Operations.visit(admin, opened_equipment["id"], equipment.workflow_id).session.ticket_id

    for {op, rev} <- [{"create", 0}, {"verify", 1}],
        do:
          assert(
            {:ok, _} = Participants.command(admin, participant(ticket, customer.id, op, rev))
          )

    {:ok, _} =
      FinanceFixtures.save(admin, ticket, "work_order", %{
        "fault_report" => "Immutable recovery result"
      })

    {:ok, _} =
      WorkflowFixtures.transition(admin, ticket, "request_details", "Synthetic correction")

    {:ok, document} =
      PrivateDocuments.upload(
        customer,
        ticket,
        "repair_packet",
        "proof",
        "recovery.pdf",
        Instantflow.EnrollmentFixtures.pdf()
      )

    {:ok, _} = PrivateDocuments.review(admin, document.object_key, true)
    {:ok, data} = WorkflowRuntime.get(admin, ticket)

    {:ok, _} =
      Delivery.Curated.release(
        admin,
        ticket,
        "repair_notice",
        customer.id,
        data.ticket.revision,
        Ecto.UUID.generate()
      )

    [message] = Delivery.Curated.inbox(customer, equipment.workflow_id).rows
    date = Operations.today(admin)

    {:ok, resource} =
      operation(admin, restaurant, "add_resource", %{"name" => "Recovery resource"})

    open_command = %{
      "workflow_id" => restaurant.workflow_id,
      "operation" => "open_session",
      "key" => Ecto.UUID.generate(),
      "resource_id" => resource["id"],
      "responsible_actor" => "Synthetic operator",
      "business_date" => Date.to_iso8601(date)
    }

    {:ok, opened} = Operations.command(admin, open_command)

    products =
      for {name, price, destination} <- [{"Soup", 500, "Kitchen"}, {"Roast", 1000, "Parrilla"}] do
        {:ok, product} =
          operation(admin, restaurant, "save_product", %{
            "name" => name,
            "category" => "Synthetic",
            "price" => price,
            "destination" => destination
          })

        %{
          "product_id" => product["id"],
          "product_revision" =>
            Enum.find(
              Operations.workspace(admin, date, restaurant.workflow_id).products,
              &(&1.id == product["id"])
            ).revision,
          "quantity" => 1,
          "notes" => "Captured"
        }
      end

    {:ok, %{"ids" => batches}} =
      operation(admin, restaurant, "submit_batch", %{
        "session_id" => opened["id"],
        "responsible_actor" => "Synthetic operator",
        "lines" => products
      })

    assert length(batches) == 2

    for batch <- batches,
        do: assert({:ok, _} = operation(admin, restaurant, "handoff", %{"batch_id" => batch}))

    {:ok, _} =
      operation(admin, restaurant, "settle", %{
        "session_id" => opened["id"],
        "expected_total" => 1500,
        "payment_method" => "pix"
      })

    {:ok, _} =
      operation(admin, restaurant, "close_day", %{"business_date" => Date.to_iso8601(date)})

    %{
      admin: admin,
      customer: customer,
      equipment: equipment,
      restaurant: restaurant,
      ticket: ticket,
      document: document,
      message: message,
      date: date,
      open_command: open_command,
      session: opened["id"]
    }
  end

  defp participant(ticket, member, operation, revision),
    do:
      BuilderFixtures.participant_command(ticket, member, operation, revision)
      |> Map.put("relationship", "owner")

  defp operation(actor, version, name, attrs),
    do:
      Operations.command(
        actor,
        Map.merge(attrs, %{
          "workflow_id" => version.workflow_id,
          "operation" => name,
          "key" => Ecto.UUID.generate()
        })
      )

  defp snapshot(tables),
    do:
      Map.new(
        tables,
        &{&1,
         OperatorRepo.query!("SELECT to_jsonb(t) FROM #{&1} t ORDER BY to_jsonb(t)::text").rows}
      )

  defp repo(module, database, name) do
    options = [name: name, database: database, pool_size: 2]

    options =
      if module == Repo,
        do:
          options ++
            [
              username: "instantflow_runtime",
              password: System.get_env("RUNTIME_DB_PASSWORD", "instantflow-runtime-local-only"),
              pool: DBConnection.ConnectionPool
            ],
        else: options

    start_supervised!(Supervisor.child_spec({module, options}, id: name))
  end

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
