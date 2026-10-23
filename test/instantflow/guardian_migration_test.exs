defmodule Instantflow.GuardianMigrationTest do
  use ExUnit.Case, async: false
  alias Instantflow.{Identity, OperatorRepo, PrivateDocuments, Repo, WorkflowRuntime}
  alias Instantflow.Identity.{Department, Membership, Organization, User}
  alias Instantflow.Enrollment.{Document, GuardianLink}
  alias Instantflow.Participants.Relationship

  test "populated guardian mapping preserves history and survives backup recovery" do
    config = OperatorRepo.config() |> Keyword.take([:username, :password, :hostname, :port])

    control =
      start_supervised!(
        Supervisor.child_spec(
          {Postgrex, config ++ [database: "postgres"]},
          id: :guardian_migration_control
        )
      )

    suffix = Integer.to_string(System.unique_integer([:positive]))
    source = "instantflow_guardian_source_" <> suffix
    restored = "instantflow_guardian_restore_" <> suffix
    backup = Path.join(System.tmp_dir!(), source <> ".dump")
    Postgrex.query!(control, "CREATE DATABASE #{source} TEMPLATE template0 ENCODING 'UTF8'")

    owner =
      start_supervised!(
        Supervisor.child_spec(
          {OperatorRepo, [name: :guardian_migration_owner, database: source, pool_size: 2]},
          id: :guardian_migration_owner
        )
      )

    previous_owner = OperatorRepo.get_dynamic_repo()
    previous_runtime = Repo.get_dynamic_repo()
    OperatorRepo.put_dynamic_repo(owner)
    migrations = Application.app_dir(:instantflow, "priv/repo/migrations")

    try do
      migrate(migrations, to: 20_261_021_224_308, log: false)
      Instantflow.HistoricalSchema.prepare_seed()
      runtime = start_runtime(source, :guardian_migration_runtime)
      Repo.put_dynamic_repo(runtime)
      f = populate()
      Instantflow.HistoricalSchema.finish_seed()

      tables =
        ~w(workflow_versions tickets ticket_sections enrollments guardian_links private_documents transition_events command_receipts outbox_messages memberships)

      before = snapshot(tables)
      migrate(migrations, all: true, log: false)
      stable = tables -- ["outbox_messages"]
      assert Instantflow.HistoricalSchema.legacy_snapshot(stable) == Map.take(before, stable)

      assert Enum.all?(
               OperatorRepo.all(Instantflow.Delivery.Message),
               &(&1.status == "cancelled")
             )

      assert OperatorRepo.query!("SELECT count(*) FROM retired_workflow_versions").rows == [[2]]
      assert :ok = Instantflow.HistoricalSchema.assert_defaults()

      mapped = OperatorRepo.all(Relationship)
      assert length(mapped) == 4
      verified = Enum.find(mapped, &(&1.legacy_guardian_link_id == f.verified.id))
      pending = Enum.find(mapped, &(&1.legacy_guardian_link_id == f.pending.id))
      revoked = Enum.find(mapped, &(&1.legacy_guardian_link_id == f.revoked.id))
      assert verified.status == "verified"
      assert verified.verified_by_id == nil
      assert verified.verified_at == f.verified.verified_at
      assert pending.status == "pending"
      assert revoked.status == "revoked"
      assert Enum.all?(mapped, &(&1.relationship == "legacy_guardian" and &1.revision == 1))
      assert {:error, :not_found} = WorkflowRuntime.get(f.parent, f.record.ticket_id)
      assert {:error, :not_found} = PrivateDocuments.download(f.parent, f.object_key)
      assert OperatorRepo.get_by!(Document, object_key: f.object_key).content == f.bytes
      assert {:error, :not_found} = WorkflowRuntime.get(f.other_parent, f.record.ticket_id)
      assert Repo.all(Relationship) == []

      assert {:ok, [other_mapping]} =
               Instantflow.Tenant.raw(f.other_org.id, fn ->
                 Repo.all(Relationship)
               end)

      assert other_mapping.ticket_id == f.other_record.ticket_id

      # Freeze a backup after migration and verify every table, including mappings/audit.
      all_tables = tables ++ ~w(ticket_participants organization_events)
      migrated = snapshot(all_tables)

      archive_rows =
        OperatorRepo.query!(
          "SELECT row_to_json(r) FROM retired_workflow_versions r ORDER BY version_id"
        ).rows

      pg!("pg_dump", ["-Fc", "--no-owner", "-d", source, "-f", backup], config)
      Postgrex.query!(control, "CREATE DATABASE #{restored} TEMPLATE template0 ENCODING 'UTF8'")
      pg!("pg_restore", ["--exit-on-error", "--no-owner", "-d", restored, backup], config)

      restored_owner =
        start_supervised!(
          Supervisor.child_spec(
            {OperatorRepo, [name: :guardian_restored_owner, database: restored, pool_size: 2]},
            id: :guardian_restored_owner
          )
        )

      OperatorRepo.put_dynamic_repo(restored_owner)
      assert snapshot(all_tables) == migrated

      assert OperatorRepo.query!(
               "SELECT row_to_json(r) FROM retired_workflow_versions r ORDER BY version_id"
             ).rows == archive_rows

      restored_runtime = start_runtime(restored, :guardian_restored_runtime)
      Repo.put_dynamic_repo(restored_runtime)
      assert {:error, :not_found} = PrivateDocuments.download(f.parent, f.object_key)
      assert {:error, :not_found} = PrivateDocuments.download(f.other_parent, f.other_object_key)
      assert OperatorRepo.get_by!(Document, object_key: f.object_key).content == f.bytes
      assert OperatorRepo.get_by!(Document, object_key: f.other_object_key).content == f.bytes
      assert {:ok, historical} = WorkflowRuntime.get(f.admin, f.record.ticket_id)
      assert historical.archived?
      assert historical.editable == []
      assert historical.transitions == []
      assert historical.assignments == []
      refute historical.can_retry
      assert {:ok, {0, nil}} = PrivateDocuments.purge_expired(f.admin.organization_id)
      assert OperatorRepo.get_by!(Document, object_key: f.object_key).content == f.bytes

      assert {:error, :retired_version} =
               WorkflowRuntime.command(f.admin, %{
                 "operation" => "save_section",
                 "ticket_id" => f.record.ticket_id,
                 "section" => "application",
                 "values" => %{"student_name" => "must not mutate"},
                 "expected_stage_revision" => 1,
                 "expected_section_revision" => 1,
                 "key" => "archived-write"
               })

      assert_raise Postgrex.Error, fn ->
        Instantflow.Tenant.transaction(f.admin, fn _ ->
          Repo.update!(
            Ecto.Changeset.change(Repo.get!(GuardianLink, f.verified.id), active: false)
          )
        end)
      end

      assert OperatorRepo.get!(Relationship, verified.id).revision == 1
      assert OperatorRepo.get!(Relationship, verified.id).status == "verified"

      assert OperatorRepo.query!(
               "SELECT count(*) FROM pg_trigger WHERE tgname='synchronize_participant'"
             ).rows == [[0]]

      assert {:error, :retired_invitation} =
               Identity.invite(f.admin, %{
                 "email" => "old@example.test",
                 "role" => "parent",
                 "enrollment_id" => f.record.id,
                 "department_id" => f.admin.department_id
               })

      for message <- OperatorRepo.all(Instantflow.Delivery.Message) do
        assert {:ok, :already_processed} =
                 Instantflow.Delivery.process(message.organization_id, message.id)
      end

      assert snapshot(all_tables) == migrated

      assert_raise RuntimeError, ~r/forward-only/, fn ->
        Ecto.Migrator.down(
          OperatorRepo,
          20_261_022_175_214,
          Instantflow.Repo.Migrations.RetireSyntheticLegacyExecution,
          log: false
        )
      end
    after
      Repo.put_dynamic_repo(previous_runtime)
      OperatorRepo.put_dynamic_repo(previous_owner)

      for id <- [
            :guardian_restored_runtime,
            :guardian_migration_runtime,
            :guardian_restored_owner,
            :guardian_migration_owner
          ],
          do: stop_supervised(id)

      for database <- [restored, source],
          do: Postgrex.query!(control, "DROP DATABASE IF EXISTS #{database} WITH (FORCE)")

      File.rm(backup)
    end
  end

  defp populate do
    org =
      OperatorRepo.insert!(%Organization{slug: "guardian-history", name: "Histórico sintético"})

    other_org =
      OperatorRepo.insert!(%Organization{slug: "unrelated-history", name: "Outra escola"})

    department = OperatorRepo.insert!(%Department{organization_id: org.id, name: "Secretaria"})

    other_department =
      OperatorRepo.insert!(%Department{organization_id: other_org.id, name: "Secretaria"})

    admin_user = user("migration-admin@example.test")
    parent_user = user("migration-parent@example.test")

    OperatorRepo.insert!(%Membership{
      organization_id: org.id,
      department_id: department.id,
      user_id: admin_user.id,
      role: "admin"
    })

    parent_member =
      OperatorRepo.insert!(%Membership{
        organization_id: org.id,
        department_id: department.id,
        user_id: parent_user.id,
        role: "parent"
      })

    OperatorRepo.insert!(%Membership{
      organization_id: other_org.id,
      department_id: other_department.id,
      user_id: parent_user.id,
      role: "parent"
    })

    admin = Identity.scope(admin_user.id, org.id)
    parent = Identity.scope(parent_user.id, org.id)
    other_parent = Identity.scope(parent_user.id, other_org.id)

    departments =
      Map.new(~w(admissions academic finance it), &{&1 <> "_department", department.id})

    record = historical_record(admin, departments)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    verified =
      OperatorRepo.insert!(%GuardianLink{
        organization_id: org.id,
        enrollment_id: record.id,
        membership_id: parent_member.id,
        active: true,
        verified_at: now
      })

    pending_user = user("migration-pending@example.test")
    revoked_user = user("migration-revoked@example.test")

    [pending, revoked] =
      for {user, active} <- [{pending_user, true}, {revoked_user, false}] do
        member =
          OperatorRepo.insert!(%Membership{
            organization_id: org.id,
            department_id: department.id,
            user_id: user.id,
            role: "parent"
          })

        OperatorRepo.insert!(%GuardianLink{
          organization_id: org.id,
          enrollment_id: record.id,
          membership_id: member.id,
          active: active
        })
      end

    bytes = Instantflow.EnrollmentFixtures.pdf()
    object_key = Ecto.UUID.generate()

    OperatorRepo.insert!(%Document{
      organization_id: org.id,
      ticket_id: record.ticket_id,
      section_key: "application",
      field_key: "document",
      object_key: object_key,
      filename: "sintetico.pdf",
      media_type: "application/pdf",
      content: bytes,
      sha256: :crypto.hash(:sha256, bytes),
      size: byte_size(bytes),
      status: "ready",
      uploaded_by_id: parent_user.id,
      reviewed_by_id: admin_user.id,
      expires_at: DateTime.add(now, -86400)
    })

    OperatorRepo.insert!(%Membership{
      organization_id: other_org.id,
      department_id: other_department.id,
      user_id: pending_user.id,
      role: "admin"
    })

    other_admin = Identity.scope(pending_user.id, other_org.id)

    other_departments =
      Map.new(
        ~w(admissions academic finance it),
        &{&1 <> "_department", other_department.id}
      )

    other_record = historical_record(other_admin, other_departments)

    other_member =
      OperatorRepo.get_by!(Membership, organization_id: other_org.id, user_id: parent_user.id)

    OperatorRepo.insert!(%GuardianLink{
      organization_id: other_org.id,
      enrollment_id: other_record.id,
      membership_id: other_member.id,
      active: true,
      verified_at: now,
      verified_by_id: pending_user.id
    })

    other_object_key = Ecto.UUID.generate()

    OperatorRepo.insert!(%Document{
      organization_id: other_org.id,
      ticket_id: other_record.ticket_id,
      section_key: "application",
      field_key: "document",
      object_key: other_object_key,
      filename: "outra-escola.pdf",
      media_type: "application/pdf",
      content: bytes,
      sha256: :crypto.hash(:sha256, bytes),
      size: byte_size(bytes),
      status: "ready",
      uploaded_by_id: parent_user.id,
      reviewed_by_id: pending_user.id,
      expires_at: DateTime.add(now, -86400)
    })

    for {actor, enrollment, document_key, name} <- [
          {admin, record, object_key, "Estudante sintético A"},
          {other_admin, other_record, other_object_key, "Estudante sintético B"}
        ] do
      section =
        OperatorRepo.get_by!(Instantflow.WorkflowRuntime.Section,
          ticket_id: enrollment.ticket_id,
          key: "application"
        )

      OperatorRepo.update!(
        Ecto.Changeset.change(section,
          values: %{
            "student_name" => name,
            "guardian_name" => "Responsável sintético",
            "school_year" => "6º ano",
            "document" => document_key
          }
        )
      )

      assert actor.organization_id == enrollment.organization_id
    end

    %{
      admin: admin,
      parent: parent,
      other_parent: other_parent,
      other_org: other_org,
      other_record: other_record,
      other_object_key: other_object_key,
      record: record,
      verified: verified,
      pending: pending,
      revoked: revoked,
      object_key: object_key,
      bytes: bytes
    }
  end

  # Historical records are seeded with the operator repository, never by reactivating retired application APIs.
  defp historical_record(actor, departments) do
    d = File.read!(Path.expand("../fixtures/history/enrollment.json", __DIR__)) |> Jason.decode!()

    workflow =
      OperatorRepo.insert!(%Instantflow.WorkflowCatalog.Workflow{
        organization_id: actor.organization_id,
        key: "enrollment",
        name: d["name"]
      })

    version =
      OperatorRepo.insert!(%Instantflow.WorkflowCatalog.Version{
        organization_id: actor.organization_id,
        workflow_id: workflow.id,
        published_by_id: actor.user_id,
        number: 1,
        definition: d,
        bindings: %{
          "roles" => %{
            "guardian" => ["parent"],
            "admissions" => ["admin", "admissions"],
            "academic" => ["head"],
            "finance" => ["finance"],
            "it" => ["it"]
          },
          "departments" => departments
        }
      })

    ticket =
      OperatorRepo.insert!(%Instantflow.WorkflowRuntime.Ticket{
        organization_id: actor.organization_id,
        workflow_id: workflow.id,
        workflow_version_id: version.id,
        requester_id: actor.user_id,
        assigned_department_id: actor.department_id,
        stage: "draft"
      })

    for section <- d["sections"] do
      OperatorRepo.insert!(%Instantflow.WorkflowRuntime.Section{
        organization_id: actor.organization_id,
        ticket_id: ticket.id,
        key: section["key"]
      })
    end

    event =
      OperatorRepo.insert!(%Instantflow.WorkflowRuntime.Event{
        organization_id: actor.organization_id,
        ticket_id: ticket.id,
        actor_id: actor.user_id,
        operation: "create",
        to_stage: "draft",
        revision: 1
      })

    OperatorRepo.insert!(%Instantflow.WorkflowRuntime.Receipt{
      organization_id: actor.organization_id,
      ticket_id: ticket.id,
      actor_id: actor.user_id,
      operation: "create",
      key: "historical-create",
      digest: :crypto.hash(:sha256, "historical"),
      result: %{"ticket_id" => ticket.id, "revision" => 1}
    })

    OperatorRepo.insert!(%Instantflow.Delivery.Message{
      organization_id: actor.organization_id,
      ticket_id: ticket.id,
      event_id: event.id,
      key: "event:#{event.id}:0",
      kind: "refresh",
      behavior: "success"
    })

    OperatorRepo.insert!(%Instantflow.Enrollment.Record{
      organization_id: actor.organization_id,
      ticket_id: ticket.id
    })
  end

  defp user(email),
    do:
      OperatorRepo.insert!(
        User.changeset(
          %User{email: email},
          %{name: "Pessoa fictícia", password: "fictional-password-123"}
        )
      )

  defp start_runtime(database, name) do
    start_supervised!(
      Supervisor.child_spec(
        {Repo,
         [
           name: name,
           database: database,
           username: "instantflow_runtime",
           password: System.get_env("RUNTIME_DB_PASSWORD", "instantflow-runtime-local-only"),
           pool: DBConnection.ConnectionPool,
           pool_size: 3
         ]},
        id: name
      )
    )
  end

  defp snapshot(tables),
    do:
      Map.new(
        tables,
        &{&1, OperatorRepo.query!("SELECT to_jsonb(t) FROM #{&1} t ORDER BY id").rows}
      )

  defp migrate(path, options) do
    previous = Code.compiler_options()
    Code.compiler_options(ignore_module_conflict: true)

    try do
      Ecto.Migrator.run(OperatorRepo, path, :up, options)
    after
      Code.compiler_options(previous)
    end
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
