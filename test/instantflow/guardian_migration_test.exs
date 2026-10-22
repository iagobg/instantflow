defmodule Instantflow.GuardianMigrationTest do
  use ExUnit.Case, async: false
  alias Instantflow.{Enrollment, Identity, OperatorRepo, PrivateDocuments, Repo}
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
      runtime = start_runtime(source, :guardian_migration_runtime)
      Repo.put_dynamic_repo(runtime)
      f = populate()

      tables =
        ~w(workflow_versions tickets ticket_sections enrollments guardian_links private_documents transition_events command_receipts outbox_messages memberships)

      before = snapshot(tables)
      migrate(migrations, all: true, log: false)
      assert snapshot(tables) == before

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
      assert {:ok, _} = Enrollment.get(f.parent, f.record.id)
      assert {:ok, document} = PrivateDocuments.download(f.parent, f.object_key)
      assert document.content == f.bytes
      assert {:error, _} = Enrollment.get(f.other_parent, f.record.id)
      assert Repo.all(Relationship) == []

      assert {:ok, [other_mapping]} =
               Instantflow.Tenant.raw(f.other_org.id, fn ->
                 Repo.all(Relationship)
               end)

      assert other_mapping.ticket_id == f.other_record.ticket_id

      # Freeze a backup after migration and verify every table, including mappings/audit.
      all_tables = tables ++ ~w(ticket_participants organization_events)
      migrated = snapshot(all_tables)
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
      restored_runtime = start_runtime(restored, :guardian_restored_runtime)
      Repo.put_dynamic_repo(restored_runtime)
      assert {:ok, recovered} = PrivateDocuments.download(f.parent, f.object_key)
      assert recovered.content == f.bytes
      assert {:ok, other_file} = PrivateDocuments.download(f.other_parent, f.other_object_key)
      assert other_file.content == f.bytes

      assert {:ok, _} = Enrollment.verify(f.admin, f.verified.id, false)
      assert {:error, _} = Enrollment.get(f.parent, f.record.id)
      assert {:error, _} = PrivateDocuments.download(f.parent, f.object_key)
      current = OperatorRepo.get!(Relationship, verified.id)
      assert current.status == "revoked" and current.revision == 2
      assert {:ok, _} = Enrollment.get(f.other_parent, f.other_record.id)
      assert {:ok, _} = PrivateDocuments.download(f.other_parent, f.other_object_key)
      assert {:ok, _} = Enrollment.verify(f.admin, f.verified.id, true)
      assert {:ok, _} = Enrollment.get(f.parent, f.record.id)
      assert OperatorRepo.get!(Relationship, verified.id).revision == 3

      # New post-upgrade invitation acceptance also creates a pending mapping.
      {:ok, invitation} = Enrollment.invite(f.admin, f.record.id, "new-guardian@example.test")

      {:ok, user} =
        Identity.accept_invitation(
          invitation.token,
          %{"name" => "Novo responsável", "password" => "fictional-password-123"}
        )

      member = Identity.scope(user.id, f.admin.organization_id)
      link = OperatorRepo.get_by!(GuardianLink, membership_id: member.id)

      assert OperatorRepo.get_by!(Relationship, legacy_guardian_link_id: link.id).status ==
               "pending"

      assert {:error, _} = Enrollment.get(member, f.record.id)

      assert_raise RuntimeError, ~r/forward-only/, fn ->
        Ecto.Migrator.run(OperatorRepo, migrations, :down, step: 1, log: false)
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

    {:ok, version} = Enrollment.install(admin, departments)
    {:ok, record} = Enrollment.create(admin, version.workflow_id, Ecto.UUID.generate())
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
      expires_at: DateTime.add(now, 86400)
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

    {:ok, other_version} = Enrollment.install(other_admin, other_departments)

    {:ok, other_record} =
      Enrollment.create(other_admin, other_version.workflow_id, Ecto.UUID.generate())

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
      expires_at: DateTime.add(now, 86400)
    })

    for {actor, enrollment, document_key, name} <- [
          {admin, record, object_key, "Estudante sintético A"},
          {other_admin, other_record, other_object_key, "Estudante sintético B"}
        ] do
      {:ok, _} =
        Instantflow.WorkflowRuntime.command(actor, %{
          "operation" => "save_section",
          "ticket_id" => enrollment.ticket_id,
          "section" => "application",
          "values" => %{
            "student_name" => name,
            "guardian_name" => "Responsável sintético",
            "school_year" => "6º ano",
            "document" => document_key
          },
          "expected_stage_revision" => 1,
          "expected_section_revision" => 1,
          "key" => Ecto.UUID.generate()
        })
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
