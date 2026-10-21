defmodule Instantflow.DeliveryRehearsal do
  @moduledoc false
  alias Instantflow.{Finance, Identity, OperatorRepo, PrivateDocuments, Repo, WorkflowRuntime}
  alias Instantflow.Identity.{Organization, User}
  alias Instantflow.WorkflowCatalog.Workflow

  def run do
    Application.put_env(:instantflow, :delivery_worker, false)
    {:ok, _} = Application.ensure_all_started(:instantflow)
    config = OperatorRepo.config() |> Keyword.take([:username, :password, :hostname, :port])
    {:ok, control} = Postgrex.start_link(config ++ [database: "postgres"])
    suffix = Base.encode16(:crypto.strong_rand_bytes(5), case: :lower)
    source = "instantflow_delivery_source_" <> suffix
    restored = "instantflow_delivery_restore_" <> suffix
    serving = System.get_env("SOURCE_DATABASE", "instantflow_dev")
    unless Regex.match?(~r/^[a-z][a-z0-9_]*$/, serving), do: raise("invalid source database")
    directory = Path.expand(".local/backups")
    File.mkdir_p!(directory)
    base = Path.join(directory, "delivery-base-#{suffix}.dump")
    backup = Path.join(directory, "delivery-populated-#{suffix}.dump")
    pg!("pg_dump", ["-Fc", "-d", serving, "-f", base], config)
    Postgrex.query!(control, "CREATE DATABASE #{source} TEMPLATE template0 ENCODING 'UTF8'")
    pg!("pg_restore", ["--exit-on-error", "-d", source, base], config)

    {:ok, owner} =
      OperatorRepo.start_link(name: :delivery_rehearsal_operator, database: source, pool_size: 2)

    OperatorRepo.put_dynamic_repo(owner)

    {:ok, runtime} =
      Repo.start_link(
        name: :delivery_rehearsal_runtime,
        database: source,
        pool: DBConnection.ConnectionPool,
        username: "instantflow_runtime",
        password: System.get_env("RUNTIME_DB_PASSWORD", "instantflow-runtime-local-only"),
        pool_size: 4
      )

    Repo.put_dynamic_repo(runtime)
    fixture = populate!()
    before = snapshot()

    for table <-
          ~w(private_documents budget_accounts budget_holds budget_entries section_assignments enrollments guardian_links command_receipts transition_events outbox_messages) do
      unless before[table].count > 0, do: raise("missing populated recovery table: #{table}")
    end

    pg!("pg_dump", ["-Fc", "-d", source, "-f", backup], config)
    Postgrex.query!(control, "CREATE DATABASE #{restored} TEMPLATE template0 ENCODING 'UTF8'")
    pg!("pg_restore", ["--exit-on-error", "-d", restored, backup], config)

    {:ok, restored_owner} =
      OperatorRepo.start_link(name: :delivery_restored_operator, database: restored, pool_size: 2)

    OperatorRepo.put_dynamic_repo(restored_owner)
    unless snapshot() == before, do: raise("restore changed rows")

    rollback_refused =
      try do
        Ecto.Migrator.run(
          OperatorRepo,
          Application.app_dir(:instantflow, "priv/repo/migrations"),
          :down,
          step: 1,
          log: false
        )

        false
      rescue
        error in RuntimeError -> String.contains?(Exception.message(error), "forward-only")
      end

    unless rollback_refused && snapshot() == before, do: raise("rollback altered recovered data")

    {:ok, restored_runtime} =
      Repo.start_link(
        name: :delivery_restored_runtime,
        database: restored,
        pool: DBConnection.ConnectionPool,
        username: "instantflow_runtime",
        password: System.get_env("RUNTIME_DB_PASSWORD", "instantflow-runtime-local-only"),
        pool_size: 4
      )

    Repo.put_dynamic_repo(restored_runtime)
    unless Repo.all(Instantflow.Collaboration.Assignment) == [], do: raise("RLS context leaked")
    {:ok, download} = PrivateDocuments.download(fixture.counselor, fixture.object_key)
    unless download.content == fixture.bytes, do: raise("private bytes differ after restore")
    {:ok, data} = WorkflowRuntime.get(fixture.counselor, fixture.incident_id)

    unless Enum.find(data.sections, &(&1.key == "support")).values["notes"] ==
             "Nota sintética de recuperação",
           do: raise("private note differs")

    accounts = Finance.accounts(fixture.finance)
    unless Enum.any?(accounts, &(&1.spent >= 6000)), do: raise("posted spend missing")

    report = %{
      serving_database_read_only: serving,
      fixture_database: source,
      restored_database: restored,
      backup: backup,
      source_rows_equal_restored_rows: true,
      private_bytes_downloaded_after_restore: true,
      runtime_rls_absent_context_denied: true,
      rollback_refused_without_data_change: rollback_refused,
      organizations: OperatorRepo.aggregate(Organization, :count),
      integrated_walkthrough: fixture.scenarios,
      tables: before,
      limitations:
        "Whole-database recovery of synthetic records. Does not demonstrate tenant-selective restore, encrypted/off-host backups or production recovery objectives."
    }

    path = ".local/delivery-recovery.json"
    File.write!(path, Jason.encode!(report, pretty: true))
    IO.puts(Jason.encode!(Map.drop(report, [:tables]), pretty: true))
    IO.puts("Full report: #{path}")
    for pid <- [restored_runtime, runtime, restored_owner, owner], do: Supervisor.stop(pid)
    GenServer.stop(control)
  end

  defp populate! do
    org = OperatorRepo.get_by!(Organization, slug: "horizonte")
    teacher = actor!("docente@escola.example", org.id)
    dean = actor!("direcao@escola.example", org.id)
    counselor = actor!("orientacao@escola.example", org.id)
    finance = actor!("financeiro@escola.example", org.id)
    head = actor!("coordenacao@escola.example", org.id)
    operations = actor!("operacoes@escola.example", org.id)
    incident = create!(teacher, org.id, "incident")

    save!(teacher, incident, "report", %{
      "facts" => "Relato fictício de recuperação",
      "students" => "Estudante fictício",
      "location" => "Pátio",
      "occurred_at" => "2026-10-21T12:00:00Z",
      "urgency" => "Rotina"
    })

    transition!(teacher, incident, "submit")
    {:ok, data} = WorkflowRuntime.get(dean, incident)

    command!(dean, %{
      "operation" => "assign",
      "ticket_id" => incident,
      "section" => "support",
      "membership_id" => counselor.id,
      "expected_revision" => data.ticket.revision,
      "reason" => "Acompanhamento de teste de recuperação"
    })

    save!(dean, incident, "discipline", %{"triage" => "Triagem fictícia"})
    transition!(dean, incident, "triage")
    bytes = "%PDF-1.4\nCONTEUDO FICTICIO RECUPERACAO\n%%EOF"

    {:ok, file} =
      PrivateDocuments.upload(
        counselor,
        incident,
        "support",
        "attachment",
        "recuperacao.pdf",
        bytes
      )

    {:ok, _} = PrivateDocuments.review(counselor, file.object_key, true)

    save!(counselor, incident, "support", %{
      "notes" => "Nota sintética de recuperação",
      "attachment" => file.object_key
    })

    requisition = create!(teacher, org.id, "requisition")

    save!(teacher, requisition, "request", %{
      "summary" => "Material fictício de recuperação",
      "justification" => "Ensaio de backup",
      "quantity" => 4,
      "amount" => 6000
    })

    transition!(teacher, requisition, "submit")
    transition!(head, requisition, "academic_approve")
    transition!(finance, requisition, "reserve")
    save!(operations, requisition, "order", %{"reference" => "Pedido simulado de recuperação"})
    transition!(operations, requisition, "order")
    save!(operations, requisition, "delivery", %{"received" => 2})

    {:error, :incomplete_delivery} =
      WorkflowRuntime.command(operations, transition_command(operations, requisition, "finish"))

    save!(operations, requisition, "delivery", %{"received" => 4})
    transition!(operations, requisition, "finish")

    save!(dean, incident, "discipline", %{
      "triage" => "Triagem fictícia",
      "resolution" => "Resolução fictícia"
    })

    save!(dean, incident, "communication", %{
      "recipient" => "Contato fictício",
      "message" => "Comunicação curada sintética"
    })

    transition!(dean, incident, "communicate")

    {:error, :guard_failed} =
      WorkflowRuntime.command(dean, transition_command(dean, incident, "close"))

    drain!(org.id)
    retry!(dean, incident, "simulate_notification")
    drain!(org.id)
    transition!(dean, incident, "close")
    trip = create!(teacher, org.id, "field_trip")

    save!(teacher, trip, "request", %{
      "summary" => "Passeio fictício",
      "justification" => "Ensaio integrado",
      "quantity" => 4,
      "amount" => 8000,
      "date" => "2027-01-12",
      "destination" => "Museu fictício",
      "itinerary" => "Saída às 09h",
      "risks" => "Acompanhamento por docentes"
    })

    transition!(teacher, trip, "submit")
    transition!(head, trip, "academic_approve")
    transition!(finance, trip, "reserve")
    save!(operations, trip, "order", %{"reference" => "Transporte fictício"})
    transition!(operations, trip, "order")
    save!(dean, trip, "safety", %{"confirmed" => true})
    transition!(dean, trip, "approve")
    enrollment_walkthrough!(org, head, finance)
    fifth_walkthrough!(org, teacher, head)

    for {actor, id, stage} <- [
          {dean, incident, "closed"},
          {operations, requisition, "complete"},
          {dean, trip, "complete"}
        ] do
      {:ok, data} = WorkflowRuntime.get(actor, id)
      unless data.ticket.stage == stage, do: raise("walkthrough did not complete")
    end

    %{
      counselor: counselor,
      finance: finance,
      object_key: file.object_key,
      bytes: bytes,
      incident_id: incident,
      scenarios: %{
        enrollment_complete_with_retry_and_replay: true,
        requisition_partial_gate_and_completion: true,
        trip_all_prerequisites_complete: true,
        incident_curated_simulation_and_closure: true,
        fifth_authored_and_imported: true,
        independent_customization_and_shared_identity_denial: true
      }
    }
  end

  defp actor!(email, org_id),
    do: Identity.scope(OperatorRepo.get_by!(User, email: email).id, org_id)

  defp create!(actor, org_id, key) do
    workflow = OperatorRepo.get_by!(Workflow, organization_id: org_id, key: key)
    command!(actor, %{"operation" => "create", "workflow_id" => workflow.id})["ticket_id"]
  end

  defp save!(actor, id, key, values) do
    {:ok, data} = WorkflowRuntime.get(actor, id)
    section = Enum.find(data.sections, &(&1.key == key))

    command!(actor, %{
      "operation" => "save_section",
      "ticket_id" => id,
      "section" => key,
      "values" => values,
      "expected_stage_revision" => data.ticket.stage_revision,
      "expected_section_revision" => section.revision
    })
  end

  defp transition!(actor, id, key), do: command!(actor, transition_command(actor, id, key))

  defp transition_command(actor, id, key) do
    {:ok, data} = WorkflowRuntime.get(actor, id)

    %{
      "operation" => "transition",
      "key" => Ecto.UUID.generate(),
      "ticket_id" => id,
      "transition" => key,
      "expected_revision" => data.ticket.revision,
      "section_revisions" => Map.new(data.sections, &{&1.key, &1.revision}),
      "reason" => nil
    }
  end

  defp drain!(org_id) do
    Enum.reduce_while(1..100, :ok, fn _, _ ->
      case Instantflow.Delivery.pending_ids(org_id) do
        [] ->
          {:halt, :ok}

        ids ->
          Enum.each(ids, &Instantflow.Delivery.process(org_id, &1))
          {:cont, :ok}
      end
    end)
  end

  defp retry!(actor, id, kind) do
    {:ok, data} = WorkflowRuntime.get(actor, id)
    message = Enum.find(data.deliveries, &(&1.kind == kind))
    unless message && message.status == "failed", do: raise("expected a failed simulation")
    {:ok, _} = Instantflow.Delivery.retry(actor, message.id)
  end

  defp enrollment_walkthrough!(org, academic, finance) do
    alias Instantflow.Enrollment
    admissions = actor!("admin@escola.example", org.id)
    parent = actor!("responsavel.a@escola.example", org.id)
    unrelated = actor!("responsavel.b@escola.example", org.id)
    it = actor!("ti@escola.example", org.id)
    workflow = OperatorRepo.get_by!(Workflow, organization_id: org.id, key: "enrollment")
    {:ok, enrollment} = Enrollment.create(admissions, workflow.id, Ecto.UUID.generate())
    {:ok, invitation} = Enrollment.invite(admissions, enrollment.id, parent.user.email)
    {:ok, _} = Identity.accept_invitation(invitation.token, %{}, parent.user)

    link =
      Enum.find(Enrollment.guardians(admissions, enrollment.id), &(&1.membership_id == parent.id))

    {:ok, _} = Enrollment.verify(admissions, link.id, true)

    {:ok, file} =
      Enrollment.upload(parent, enrollment.id, "matricula.pdf", "%PDF-1.4 FICTICIO %%EOF")

    {:ok, data} = Enrollment.get(parent, enrollment.id)

    {:ok, _} =
      Enrollment.save(
        parent,
        enrollment.id,
        %{
          "student_name" => "Estudante integrado fictício",
          "guardian_name" => "Responsável fictício",
          "school_year" => "2027",
          "document" => file.object_key
        },
        data.stage_revision,
        data.section_revision,
        Ecto.UUID.generate()
      )

    {:ok, data} = Enrollment.get(parent, enrollment.id)

    {:ok, _} =
      Enrollment.submit(
        parent,
        enrollment.id,
        data.revision,
        data.section_revision,
        Ecto.UUID.generate()
      )

    id = enrollment.ticket_id
    save!(admissions, id, "identity", %{"display_name" => "Estudante fictício"})

    {:error, :attachment_not_ready} =
      WorkflowRuntime.command(admissions, transition_command(admissions, id, "verify"))

    {:ok, _} = PrivateDocuments.review(admissions, file.object_key, true)
    transition!(admissions, id, "verify")

    save!(academic, id, "placement", %{
      "class" => "6A",
      "assessment" => "Avaliação interna fictícia"
    })

    transition!(academic, id, "place")
    save!(finance, id, "payment", %{"reference" => "Pagamento fictício"})
    drain!(org.id)
    command = transition_command(finance, id, "paid")
    result = command!(finance, command)
    unless command!(finance, command) == result, do: raise("retry changed payment result")
    drain!(org.id)
    retry!(it, id, "simulate_provisioning")
    drain!(org.id)
    transition!(it, id, "finish")
    {:ok, public} = Enrollment.get(parent, enrollment.id)

    unless public.status == "Matrícula concluída" and not Map.has_key?(public, :events),
      do: raise("parent projection wrong")

    {:error, :not_found} = Enrollment.get(unrelated, enrollment.id)
    {:error, :not_found} = WorkflowRuntime.get(parent, id)
  end

  defp fifth_walkthrough!(org, teacher, head) do
    alias Instantflow.WorkflowCatalog.Templates
    admin = actor!("admin@escola.example", org.id)
    key = "space_demo_" <> Base.encode16(:crypto.strong_rand_bytes(3), case: :lower)
    {:ok, draft} = Templates.new(admin, key, "Reserva de espaço fictícia")

    bindings = %{
      "roles" => %{"requester" => ["teacher"], "reviewer" => ["head"]},
      "departments" => %{"responsible" => head.department_id}
    }

    {:ok, saved} = Templates.save(admin, draft.id, draft.revision, draft.definition, bindings)
    {:ok, version} = Templates.publish(admin, draft.id, saved.revision)
    {:ok, exported} = Templates.export(admin, :version, version.id)
    {:ok, imported} = Templates.import(admin, exported.json, %{"template_key" => key <> "_copy"})
    {:ok, review} = Templates.review(admin, imported.id)
    unless review.errors != [], do: raise("import unexpectedly carried operational bindings")

    {:ok, saved} =
      Templates.save(admin, imported.id, imported.revision, imported.definition, bindings)

    {:ok, copy} = Templates.publish(admin, saved.id, saved.revision)

    id =
      command!(teacher, %{"operation" => "create", "workflow_id" => copy.workflow_id})[
        "ticket_id"
      ]

    save!(teacher, id, "request", %{"summary" => "Espaço fictício"})
    transition!(head, id, "complete")
    other = OperatorRepo.get_by!(Organization, slug: "aurora")
    other_admin = actor!("gestao@aurora.example", other.id)
    shared = Identity.scope(admin.user_id, other.id)
    {:error, :forbidden} = Templates.export(shared, :version, version.id)
    {:ok, local} = Templates.import(other_admin, exported.json)

    {:error, :invalid_bindings} =
      Templates.save(other_admin, local.id, local.revision, local.definition, bindings)

    dep =
      OperatorRepo.get_by!(Instantflow.Identity.Department,
        organization_id: other.id,
        name: "Coordenação"
      )

    local_bindings = put_in(bindings, ["departments", "responsible"], dep.id)

    {:ok, local} =
      Templates.save(
        other_admin,
        local.id,
        local.revision,
        Map.put(local.definition, "name", "Reserva de espaço Aurora"),
        local_bindings
      )

    {:ok, _} = Templates.publish(other_admin, local.id, local.revision)
    original = OperatorRepo.get!(Instantflow.WorkflowCatalog.Version, version.id)

    unless original.definition["name"] == "Reserva de espaço fictícia",
      do: raise("other school altered source")
  end

  defp command!(actor, command) do
    {:ok, result} =
      WorkflowRuntime.command(actor, Map.put_new(command, "key", Ecto.UUID.generate()))

    result
  end

  defp snapshot do
    tables =
      OperatorRepo.query!(
        "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename"
      ).rows
      |> List.flatten()

    Map.new(tables, fn table ->
      column = if table == "schema_migrations", do: "version", else: "id"

      rows =
        OperatorRepo.query!(
          "SELECT row_to_json(row)::text FROM (SELECT * FROM #{table} ORDER BY #{column}) row"
        ).rows

      {table,
       %{
         count: length(rows),
         sha256:
           :crypto.hash(:sha256, :erlang.term_to_binary(rows)) |> Base.encode16(case: :lower)
       }}
    end)
  end

  defp pg!(name, args, config) do
    local = Path.expand(".local/postgres/usr/lib/postgresql/16/bin")

    directory =
      System.get_env("PG_BIN") || if(File.exists?(Path.join(local, name)), do: local, else: "")

    executable = if directory == "", do: name, else: Path.join(directory, name)

    env = [
      {"LD_LIBRARY_PATH",
       Path.expand(".local/postgres/usr/lib/x86_64-linux-gnu") <>
         ":" <> (System.get_env("LD_LIBRARY_PATH") || "")},
      {"PGUSER", config[:username]},
      {"PGPASSWORD", config[:password]},
      {"PGHOST", config[:hostname]},
      {"PGPORT", to_string(config[:port])}
    ]

    {output, status} = System.cmd(executable, args, env: env, stderr_to_stdout: true)
    unless status == 0, do: raise("#{name} failed: #{output}")
  end
end

Instantflow.DeliveryRehearsal.run()
