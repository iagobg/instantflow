defmodule Instantflow.RuntimeRoleTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Instantflow.WorkflowFixtures, only: [definition_fixture: 0]

  alias Instantflow.{
    Repo,
    OperatorRepo,
    Identity,
    Tenant,
    WorkflowCatalog,
    WorkflowRuntime,
    Delivery
  }

  alias Instantflow.Identity.{Department, Membership, Organization, User}

  setup_all do
    config = OperatorRepo.config() |> Keyword.take([:username, :password, :hostname, :port])

    control =
      start_supervised!(
        Supervisor.child_spec({Postgrex, config ++ [database: "postgres"]}, id: :control)
      )

    database = "instantflow_isolation_#{System.unique_integer([:positive])}"
    Postgrex.query!(control, "CREATE DATABASE #{database} TEMPLATE template0 ENCODING 'UTF8'")

    owner =
      start_supervised!(
        {OperatorRepo, [name: :isolation_operator, database: database, pool_size: 2]}
      )

    OperatorRepo.put_dynamic_repo(owner)

    Ecto.Migrator.run(
      OperatorRepo,
      Application.app_dir(:instantflow, "priv/repo/migrations"),
      :up,
      all: true,
      log: false
    )

    runtime =
      start_supervised!(
        {Repo,
         [
           name: :isolation_runtime,
           database: database,
           username: "instantflow_runtime",
           password: System.get_env("RUNTIME_DB_PASSWORD", "instantflow-runtime-local-only"),
           pool: DBConnection.ConnectionPool,
           pool_size: 4
         ]}
      )

    on_exit(fn ->
      # Only this generated, disposable test database is cleaned up; ordinary rollback never deletes a tenant.
      {:ok, connection} = Postgrex.start_link(config ++ [database: "postgres"])
      Postgrex.query!(connection, "DROP DATABASE IF EXISTS #{database} WITH (FORCE)")
      GenServer.stop(connection)
    end)

    %{owner: owner, runtime: runtime, database: database, owner_config: config}
  end

  setup context do
    OperatorRepo.put_dynamic_repo(context.owner)
    Repo.put_dynamic_repo(context.runtime)
    suffix = System.unique_integer([:positive])
    a = OperatorRepo.insert!(%Organization{slug: "a-#{suffix}", name: "Escola Exemplo"})
    b = OperatorRepo.insert!(%Organization{slug: "b-#{suffix}", name: "Escola Exemplo"})
    da = OperatorRepo.insert!(%Department{organization_id: a.id, name: "Secretaria"})
    db = OperatorRepo.insert!(%Department{organization_id: b.id, name: "Secretaria"})

    user =
      OperatorRepo.insert!(
        User.changeset(%User{email: "shared#{suffix}@escola.example"}, %{
          name: "Pessoa Compartilhada",
          password: "fictional-password-123"
        })
      )

    OperatorRepo.insert!(%Membership{
      organization_id: a.id,
      user_id: user.id,
      department_id: da.id,
      role: "admin"
    })

    OperatorRepo.insert!(%Membership{
      organization_id: b.id,
      user_id: user.id,
      department_id: db.id,
      role: "staff"
    })

    a_scope = Identity.scope(user.id, a.id)
    b_scope = Identity.scope(user.id, b.id)

    bindings = %{
      "roles" => %{"requester" => ["admin", "staff"], "reviewer" => ["staff"]},
      "departments" => %{"review_department" => da.id}
    }

    {:ok, version} = WorkflowCatalog.publish(a_scope, definition_fixture(), bindings)

    {:ok, result} =
      WorkflowRuntime.command(a_scope, %{
        "operation" => "create",
        "key" => "first",
        "workflow_id" => version.workflow_id
      })

    Map.merge(context, %{
      a: a,
      b: b,
      a_scope: a_scope,
      b_scope: b_scope,
      version: version,
      ticket_id: result["ticket_id"]
    })
  end

  test "a real non-owner login denies absent/wrong RLS context and cross-tenant raw SQL", c do
    connection =
      start_supervised!(
        Supervisor.child_spec(
          {Postgrex,
           Keyword.drop(c.owner_config, [:username, :password]) ++
             [
               database: c.database,
               username: "instantflow_runtime",
               password: System.get_env("RUNTIME_DB_PASSWORD", "instantflow-runtime-local-only")
             ]},
          id: :raw_runtime
        )
      )

    assert Postgrex.query!(
             connection,
             "SELECT current_user, rolsuper, rolbypassrls, (SELECT tableowner=current_user FROM pg_tables WHERE tablename='tickets' AND schemaname='public') FROM pg_roles WHERE rolname=current_user"
           ).rows == [["instantflow_runtime", false, false, false]]

    assert Postgrex.query!(connection, "SELECT count(*) FROM tickets").rows == [[0]]
    Postgrex.query!(connection, "BEGIN")

    Postgrex.query!(connection, "SELECT set_config('instantflow.organization_id',$1,true)", [
      to_string(c.b.id)
    ])

    assert Postgrex.query!(connection, "SELECT count(*) FROM tickets WHERE id=$1", [c.ticket_id]).rows ==
             [[0]]

    assert {:error, %Postgrex.Error{postgres: %{code: :foreign_key_violation}}} =
             Postgrex.query(
               connection,
               "INSERT INTO ticket_sections(organization_id,ticket_id,key,values,revision,inserted_at,updated_at) VALUES($1,$2,'forged','{}',1,now(),now())",
               [c.b.id, c.ticket_id]
             )

    Postgrex.query!(connection, "ROLLBACK")
    Postgrex.query!(connection, "BEGIN")

    Postgrex.query!(connection, "SELECT set_config('instantflow.organization_id',$1,true)", [
      to_string(c.a.id)
    ])

    assert Postgrex.query!(connection, "SELECT count(*) FROM tickets WHERE id=$1", [c.ticket_id]).rows ==
             [[1]]

    Postgrex.query!(connection, "COMMIT")
    assert Postgrex.query!(connection, "SELECT count(*) FROM tickets").rows == [[0]]

    assert Postgrex.query!(
             connection,
             "SELECT NULLIF(current_setting('instantflow.organization_id',true),'')"
           ).rows == [[nil]]

    assert {:ok, [id]} =
             Tenant.transaction(c.a_scope, fn _ ->
               Repo.all(from t in Instantflow.WorkflowRuntime.Ticket, select: t.id)
             end)

    assert id == c.ticket_id
    assert Repo.all(Instantflow.WorkflowRuntime.Ticket) == []

    assert {:error, :injected} =
             Tenant.transaction(c.a_scope, fn _ -> Repo.rollback(:injected) end)

    assert Repo.all(Instantflow.WorkflowRuntime.Ticket) == []
  end

  test "suspension serializes against independent command and result-application connections",
       c do
    connection =
      start_supervised!(
        Supervisor.child_spec({Postgrex, c.owner_config ++ [database: c.database]},
          id: :suspension
        )
      )

    message = OperatorRepo.get_by!(Instantflow.Delivery.Message, ticket_id: c.ticket_id)
    Postgrex.query!(connection, "BEGIN")

    Postgrex.query!(connection, "UPDATE organizations SET status='suspended' WHERE id=$1", [
      c.a.id
    ])

    supervisor = start_supervised!(Task.Supervisor)

    command =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Repo.put_dynamic_repo(c.runtime)

        WorkflowRuntime.command(c.a_scope, %{
          "operation" => "create",
          "key" => "blocked-command",
          "workflow_id" => c.version.workflow_id
        })
      end)

    delivery =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Repo.put_dynamic_repo(c.runtime)
        Delivery.process(c.a.id, message.id)
      end)

    assert wait_for_waiters(connection, c.database, 2, 1000)
    Postgrex.query!(connection, "COMMIT")
    assert {:error, :unavailable} = Task.await(command)
    assert {:error, :unavailable} = Task.await(delivery)
    assert OperatorRepo.get!(Instantflow.Delivery.Message, message.id).status == "pending"
    assert Identity.scope(c.a_scope.user_id, c.a.id) == nil
    assert Identity.scope(c.a_scope.user_id, c.b.id)
  end

  test "operator bootstrap is atomic/idempotent and lifecycle changes are audited", c do
    slug = "provision-#{System.unique_integer([:positive])}"

    assert {:error, :invalid_invitation} =
             Instantflow.Organizations.Operator.provision(
               "test operator",
               slug,
               "Escola",
               "invalid",
               "bootstrap"
             )

    assert OperatorRepo.get_by(Organization, slug: slug) == nil

    assert {:ok, %{organization: organization, token: token}} =
             Instantflow.Organizations.Operator.provision(
               "test operator",
               slug,
               "Escola",
               "owner@new.example",
               "bootstrap"
             )

    assert is_binary(token)

    assert {:error, :idempotency_mismatch} =
             Instantflow.Organizations.Operator.provision(
               "test operator",
               slug <> "-other",
               "Escola",
               "owner@new.example",
               "bootstrap"
             )

    assert OperatorRepo.get_by(Organization, slug: slug <> "-other") == nil

    assert {:ok, %{token: nil}} =
             Instantflow.Organizations.Operator.provision(
               "test operator",
               slug,
               "Escola",
               "owner@new.example",
               "bootstrap"
             )

    assert {:error, :idempotency_mismatch} =
             Instantflow.Organizations.Operator.provision(
               "test operator",
               slug,
               "Changed",
               "owner@new.example",
               "bootstrap"
             )

    assert {:ok, _} =
             Instantflow.Organizations.Operator.set_status(
               "test operator",
               slug,
               "suspended",
               "suspend"
             )

    assert {:ok, _} =
             Instantflow.Organizations.Operator.set_status(
               "test operator",
               slug,
               "active",
               "resume"
             )

    assert OperatorRepo.aggregate(
             from(e in Instantflow.Organizations.Event,
               where: e.organization_id == ^organization.id
             ),
             :count
           ) == 3

    assert Repo.query!("SELECT count(*) FROM organization_events").rows == [[0]]
    assert c.runtime
  end

  test "per-organization scheduling is bounded and queue exhaustion rolls back business rows",
       c do
    original_batch = Application.get_env(:instantflow, :delivery_batch_per_organization)
    original_limit = Application.get_env(:instantflow, :max_pending_deliveries_per_organization)

    on_exit(fn ->
      if original_batch,
        do: Application.put_env(:instantflow, :delivery_batch_per_organization, original_batch),
        else: Application.delete_env(:instantflow, :delivery_batch_per_organization)

      if original_limit,
        do:
          Application.put_env(
            :instantflow,
            :max_pending_deliveries_per_organization,
            original_limit
          ),
        else: Application.delete_env(:instantflow, :max_pending_deliveries_per_organization)
    end)

    Application.put_env(:instantflow, :max_pending_deliveries_per_organization, 0)

    assert {:error, :queue_full} =
             WorkflowRuntime.command(c.a_scope, %{
               "operation" => "create",
               "key" => "over-quota",
               "workflow_id" => c.version.workflow_id
             })

    assert length(WorkflowRuntime.list(c.a_scope)) == 1
    Application.put_env(:instantflow, :max_pending_deliveries_per_organization, 1000)

    for number <- 1..3,
        do:
          assert(
            {:ok, _} =
              WorkflowRuntime.command(c.a_scope, %{
                "operation" => "create",
                "key" => "backlog-#{number}",
                "workflow_id" => c.version.workflow_id
              })
          )

    workflow =
      OperatorRepo.insert!(%Instantflow.WorkflowCatalog.Workflow{
        organization_id: c.b.id,
        key: "simple_approval",
        name: "Cópia B"
      })

    OperatorRepo.insert!(%Instantflow.WorkflowCatalog.Version{
      organization_id: c.b.id,
      workflow_id: workflow.id,
      number: 1,
      definition: c.version.definition,
      bindings:
        put_in(c.version.bindings, ["departments", "review_department"], c.b_scope.department_id),
      published_by_id: c.a_scope.user_id
    })

    {:ok, result} =
      WorkflowRuntime.command(c.b_scope, %{
        "operation" => "create",
        "key" => "b-work",
        "workflow_id" => workflow.id
      })

    Application.put_env(:instantflow, :delivery_batch_per_organization, 1)
    Delivery.drain()
    assert length(Delivery.pending_ids(c.a.id)) == 1

    assert OperatorRepo.get_by!(Instantflow.Delivery.Message, ticket_id: result["ticket_id"]).status ==
             "succeeded"

    assert OperatorRepo.aggregate(
             from(m in Instantflow.Delivery.Message,
               where: m.organization_id == ^c.a.id and m.status == "succeeded"
             ),
             :count
           ) == 1
  end

  test "lost bootstrap invitations can be recovered without replay or password takeover" do
    slug = "recovery-#{System.unique_integer([:positive])}"

    {:ok, original} =
      Instantflow.Organizations.Operator.provision(
        "operator",
        slug,
        "Recovery School",
        "recover@example.com",
        "provision"
      )

    {:ok, replacement} =
      Instantflow.Organizations.Operator.reissue_bootstrap(
        "operator",
        slug,
        "recover@example.com",
        "recover"
      )

    assert {:ok, %{token: nil}} =
             Instantflow.Organizations.Operator.reissue_bootstrap(
               "operator",
               slug,
               "recover@example.com",
               "recover"
             )

    assert {:error, :idempotency_mismatch} =
             Instantflow.Organizations.Operator.reissue_bootstrap(
               "operator",
               slug,
               "other@example.com",
               "recover"
             )

    assert {:error, :invalid_invitation} = Identity.accept_invitation(original.token, %{})

    assert {:ok, _} =
             Identity.accept_invitation(replacement.token, %{
               "name" => "Pessoa Recuperada",
               "password" => "fictional-password-123"
             })

    assert {:error, :already_bootstrapped} =
             Instantflow.Organizations.Operator.reissue_bootstrap(
               "operator",
               slug,
               "other@example.com",
               "later"
             )
  end

  test "overlapping same-section saves have one winner and one conflict", c do
    {:ok, data} = WorkflowRuntime.get(c.a_scope, c.ticket_id)

    first =
      Instantflow.CollaborationFixtures.section_command(data, "request", %{"summary" => "A"})

    second = %{first | "key" => "competing", "values" => %{"summary" => "B"}}
    results = race(c, c.ticket_id, [first, second])
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert {:error, :conflict} in results
    {:ok, final} = WorkflowRuntime.get(c.a_scope, c.ticket_id)
    assert final.ticket.revision == 2
    assert hd(final.sections).revision == 2
    assert length(final.events) == 2
    assert count_receipts(c.ticket_id) == 2
  end

  test "local grants enforce RLS and composite ownership under the non-owner login", c do
    {:ok, {_, _}} =
      Instantflow.Access.grant(c.a_scope, c.a_scope.id, c.a_scope.department_id, "finance")

    connection =
      start_supervised!(
        Supervisor.child_spec(
          {Postgrex,
           Keyword.drop(c.owner_config, [:username, :password]) ++
             [
               database: c.database,
               username: "instantflow_runtime",
               password: System.get_env("RUNTIME_DB_PASSWORD", "instantflow-runtime-local-only")
             ]},
          id: :grant_rls
        )
      )

    assert Postgrex.query!(connection, "SELECT count(*) FROM membership_grants").rows == [[0]]
    Postgrex.query!(connection, "BEGIN")

    Postgrex.query!(connection, "SELECT set_config('instantflow.organization_id',$1,true)", [
      to_string(c.b.id)
    ])

    assert Postgrex.query!(connection, "SELECT count(*) FROM membership_grants").rows == [[0]]

    assert {:error, %Postgrex.Error{postgres: %{code: :foreign_key_violation}}} =
             Postgrex.query(
               connection,
               "INSERT INTO membership_grants(organization_id,membership_id,department_id,role,inserted_at,updated_at) VALUES($1,$2,$3,'finance',now(),now())",
               [c.b.id, c.a_scope.id, c.b_scope.department_id]
             )

    Postgrex.query!(connection, "ROLLBACK")
  end

  test "independent sections both commit through overlapping connections", c do
    {id, data} = collaborative_ticket(c)

    commands =
      for key <- ["request", "notes"],
          do: Instantflow.CollaborationFixtures.section_command(data, key, %{"summary" => key})

    [first, second] = commands
    peer = reviewer(c, "sections")
    assert Enum.all?(race(c, id, [first, {peer, second}]), &match?({:ok, _}, &1))
    {:ok, final} = WorkflowRuntime.get(c.a_scope, id)
    assert final.ticket.revision == 3
    assert Enum.all?(final.sections, &(&1.revision == 2))
    assert length(final.events) == 3
    assert count_receipts(id) == 3
  end

  test "overlapping duplicate delivery of the same command creates one effect and receipt", c do
    {:ok, data} = WorkflowRuntime.get(c.a_scope, c.ticket_id)

    command =
      Instantflow.CollaborationFixtures.section_command(data, "request", %{"summary" => "Uma vez"})

    [first, second] = race(c, c.ticket_id, [command, command])
    assert {:ok, _} = first
    assert first == second
    {:ok, final} = WorkflowRuntime.get(c.a_scope, c.ticket_id)
    assert final.ticket.revision == 2
    assert length(final.events) == 2
    assert count_receipts(c.ticket_id) == 2

    assert OperatorRepo.aggregate(
             from(m in Instantflow.Delivery.Message, where: m.ticket_id == ^c.ticket_id),
             :count
           ) == 2
  end

  test "competing transitions commit once and saving reviewed content invalidates a transition",
       c do
    {id, _} = collaborative_ticket(c)

    {:ok, _} =
      Instantflow.WorkflowFixtures.save(c.a_scope, id, Instantflow.WorkflowFixtures.values())

    command = Instantflow.WorkflowFixtures.transition_command(c.a_scope, id, "submit")
    results = race(c, id, [command, %{command | "key" => "second-transition"}])
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    {:ok, final} = WorkflowRuntime.get(c.a_scope, id)
    assert final.ticket.stage == "review"
    assert length(final.events) == 3

    first_reviewer = reviewer(c, "approval-a")
    second_reviewer = reviewer(c, "approval-b")
    approval = Instantflow.WorkflowFixtures.transition_command(first_reviewer, id, "approve")

    approvals =
      race(c, id, [
        {first_reviewer, approval},
        {second_reviewer, %{approval | "key" => "competing-approval"}}
      ])

    assert Enum.count(approvals, &match?({:ok, _}, &1)) == 1
    {:ok, approved} = WorkflowRuntime.get(first_reviewer, id)
    assert Enum.count(approved.events, &(&1.operation == "approve")) == 1
    assert count_receipts(id) == 4

    {other_id, _} = collaborative_ticket(c, 2)

    {:ok, _} =
      Instantflow.WorkflowFixtures.save(
        c.a_scope,
        other_id,
        Instantflow.WorkflowFixtures.values()
      )

    {:ok, data} = WorkflowRuntime.get(c.a_scope, other_id)

    save =
      Instantflow.CollaborationFixtures.section_command(data, "notes", %{
        "summary" => "Novo conteúdo"
      })

    submit = Instantflow.WorkflowFixtures.transition_command(c.a_scope, other_id, "submit")
    results = race(c, other_id, [{reviewer(c, "reviewed"), save}, submit])
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert {:error, :conflict} in results
    assert count_receipts(other_id) == 3
  end

  test "membership revocation holds the exclusive authorization gate until commit", c do
    parent = self()
    supervisor = start_supervised!(Task.Supervisor)

    # Use a distinct administrator so the target is not self-revoked.
    admin_user =
      OperatorRepo.insert!(
        User.changeset(%User{email: "gate#{c.a.id}@example.com"}, %{
          name: "Admin",
          password: "fictional-password-123"
        })
      )

    OperatorRepo.insert!(%Membership{
      organization_id: c.a.id,
      user_id: admin_user.id,
      department_id: c.a_scope.department_id,
      role: "admin"
    })

    admin = Identity.scope(admin_user.id, c.a.id)

    revoker =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Repo.put_dynamic_repo(c.runtime)

        Repo.transaction(fn ->
          result = Identity.revoke(admin, c.a_scope.id)
          send(parent, :revocation_holds_gate)

          receive do
            :commit -> result
          after
            5000 -> Repo.rollback(:barrier_timeout)
          end
        end)
      end)

    assert_receive :revocation_holds_gate, 5000

    command =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Repo.put_dynamic_repo(c.runtime)

        WorkflowRuntime.command(c.a_scope, %{
          "operation" => "create",
          "key" => "revoked",
          "workflow_id" => c.version.workflow_id
        })
      end)

    connection =
      start_supervised!(
        Supervisor.child_spec({Postgrex, c.owner_config ++ [database: c.database]},
          id: :gate_observer
        )
      )

    assert wait_for_waiters(connection, c.database, 1, 1000)
    send(revoker.pid, :commit)
    assert {:ok, {:ok, _}} = Task.await(revoker)
    assert {:error, :forbidden} = Task.await(command)
    assert count_receipts(c.ticket_id) == 1
    assert Identity.scope(c.a_scope.user_id, c.a.id) == nil
  end

  test "a grant revoked by an overlapping transaction cannot authorize a queued save", c do
    {id, _} = collaborative_ticket(c)

    {:ok, {_, grant}} =
      Instantflow.Access.grant(c.a_scope, c.a_scope.id, c.a_scope.department_id, "finance")

    {:ok, data} = WorkflowRuntime.get(c.a_scope, id)

    command =
      Instantflow.CollaborationFixtures.section_command(data, "finance", %{
        "summary" => "Revogado"
      })

    parent = self()
    supervisor = start_supervised!(Task.Supervisor)

    revoker =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Repo.put_dynamic_repo(c.runtime)

        Repo.transaction(fn ->
          result = Instantflow.Access.revoke(c.a_scope, grant.id)
          send(parent, :grant_revocation_holds_gate)

          receive do
            :commit -> result
          after
            5000 -> Repo.rollback(:barrier_timeout)
          end
        end)
      end)

    assert_receive :grant_revocation_holds_gate, 5000

    writer =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Repo.put_dynamic_repo(c.runtime)
        WorkflowRuntime.command(c.a_scope, command)
      end)

    connection =
      start_supervised!(
        Supervisor.child_spec({Postgrex, c.owner_config ++ [database: c.database]},
          id: :grant_gate_observer
        )
      )

    assert wait_for_waiters(connection, c.database, 1, 1000)
    send(revoker.pid, :commit)
    assert {:ok, {:ok, _}} = Task.await(revoker)
    assert {:error, :forbidden} = Task.await(writer)
    assert count_receipts(id) == 1

    assert OperatorRepo.get_by!(Instantflow.WorkflowRuntime.Section,
             ticket_id: id,
             key: "finance"
           ).values == %{}

    assert OperatorRepo.aggregate(
             from(e in Instantflow.WorkflowRuntime.Event, where: e.ticket_id == ^id),
             :count
           ) == 1
  end

  test "overlapping draft saves and publication use real non-owner connections and compare revisions",
       c do
    alias Instantflow.WorkflowCatalog.{Draft, Templates, TemplateEvent}
    {:ok, draft} = Templates.clone(c.a_scope, c.version.id)

    connection =
      start_supervised!(
        Supervisor.child_spec({Postgrex, c.owner_config ++ [database: c.database]},
          id: :draft_barrier
        )
      )

    Postgrex.query!(connection, "BEGIN")

    Postgrex.query!(connection, "SELECT id FROM workflow_drafts WHERE id=$1 FOR UPDATE", [
      draft.id
    ])

    supervisor = start_supervised!(Task.Supervisor)

    tasks =
      for name <- ["Edição A", "Edição B"] do
        Task.Supervisor.async_nolink(supervisor, fn ->
          Repo.put_dynamic_repo(c.runtime)

          Templates.save(
            c.a_scope,
            draft.id,
            1,
            Map.put(draft.definition, "name", name),
            draft.bindings
          )
        end)
      end

    assert wait_for_waiters(connection, c.database, 2, 1000)
    Postgrex.query!(connection, "COMMIT")
    results = Enum.map(tasks, &Task.await/1)
    assert Enum.count(results, &match?({:ok, %Draft{revision: 2}}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :conflict})) == 1
    assert {:ok, %{revision: 2} = saved} = Templates.get(c.a_scope, draft.id)

    assert OperatorRepo.aggregate(
             from(e in TemplateEvent, where: e.draft_id == ^draft.id),
             :count
           ) == 2

    assert {:error, :forbidden} = Templates.get(c.b_scope, draft.id)

    OperatorRepo.update_all(from(m in Membership, where: m.id == ^c.b_scope.id),
      set: [role: "admin"]
    )

    b_admin = Identity.scope(c.b_scope.user_id, c.b_scope.organization_id)
    assert {:error, :not_found} = Templates.get(b_admin, draft.id)
    assert Repo.all(Draft) == []
    assert Repo.all(TemplateEvent) == []

    assert_raise Ecto.ConstraintError, fn ->
      Tenant.transaction(b_admin, fn _ ->
        Repo.insert!(%Draft{
          organization_id: b_admin.organization_id,
          workflow_id: draft.workflow_id,
          base_version_id: draft.base_version_id,
          definition: draft.definition,
          bindings: draft.bindings,
          created_by_id: b_admin.user_id,
          updated_by_id: b_admin.user_id
        })
      end)
    end

    assert {:ok, []} =
             Tenant.transaction(c.b_scope, fn _ ->
               Repo.all(from d in Draft, where: d.id == ^draft.id)
             end)

    Postgrex.query!(connection, "BEGIN")

    Postgrex.query!(connection, "SELECT id FROM workflow_drafts WHERE id=$1 FOR UPDATE", [
      draft.id
    ])

    tasks =
      for _ <- 1..2 do
        Task.Supervisor.async_nolink(supervisor, fn ->
          Repo.put_dynamic_repo(c.runtime)
          Templates.publish(c.a_scope, saved.id, saved.revision)
        end)
      end

    assert wait_for_waiters(connection, c.database, 2, 1000)
    Postgrex.query!(connection, "COMMIT")
    results = Enum.map(tasks, &Task.await/1)

    assert Enum.count(
             results,
             &match?({:ok, %Instantflow.WorkflowCatalog.Version{number: 2}}, &1)
           ) == 1

    assert Enum.count(results, &(&1 == {:error, :already_published})) == 1

    assert OperatorRepo.aggregate(
             from(e in TemplateEvent,
               where: e.draft_id == ^draft.id and e.operation == "published"
             ),
             :count
           ) == 1

    assert OperatorRepo.get!(Instantflow.WorkflowRuntime.Ticket, c.ticket_id).workflow_version_id ==
             c.version.id

    assert_raise Postgrex.Error, fn ->
      Tenant.transaction(c.a_scope, fn _ ->
        Repo.query!("UPDATE workflow_drafts SET revision=revision+1 WHERE id=$1", [draft.id])
      end)
    end

    assert_raise Postgrex.Error, fn ->
      Tenant.transaction(c.a_scope, fn _ ->
        Repo.query!("DELETE FROM template_events WHERE draft_id=$1", [draft.id])
      end)
    end
  end

  test "guardian, enrollment and private object tables enforce tenant RLS under the real runtime role",
       c do
    f = enrollment_runtime(c)

    {:ok, document} =
      Instantflow.Enrollment.upload(
        f.parent,
        f.enrollment.id,
        "documento.pdf",
        Instantflow.EnrollmentFixtures.pdf()
      )

    for table <- [
          Instantflow.Enrollment.Record,
          Instantflow.Enrollment.GuardianLink,
          Instantflow.Enrollment.Document
        ] do
      assert Repo.aggregate(table, :count) == 0
      assert {:ok, 0} = Tenant.raw(c.b.id, fn -> Repo.aggregate(table, :count) end)
      assert {:ok, count} = Tenant.raw(c.a.id, fn -> Repo.aggregate(table, :count) end)
      assert count > 0
    end

    assert_raise Ecto.ConstraintError, fn ->
      Tenant.raw(c.b.id, fn ->
        Repo.insert!(%Instantflow.Enrollment.GuardianLink{
          organization_id: c.b.id,
          enrollment_id: f.enrollment.id,
          membership_id: c.b_scope.id
        })
      end)
    end

    assert {:error, :not_found} =
             Instantflow.PrivateDocuments.download(c.b_scope, document.object_key)
  end

  test "two verified guardians overlap on one section and preserve one winning revision", c do
    f = enrollment_runtime(c)

    {:ok, invitation} =
      Instantflow.Enrollment.invite(
        c.a_scope,
        f.enrollment.id,
        "second-parent#{c.a.id}@example.test"
      )

    {:ok, user} =
      Identity.accept_invitation(invitation.token, %{
        "name" => "Segundo responsável",
        "password" => "fictional-password-123"
      })

    other = Identity.scope(user.id, c.a.id)

    [link] =
      OperatorRepo.all(
        from g in Instantflow.Enrollment.GuardianLink, where: g.membership_id == ^other.id
      )

    {:ok, _} = Instantflow.Enrollment.verify(c.a_scope, link.id, true)
    {:ok, data} = WorkflowRuntime.get(c.a_scope, f.enrollment.ticket_id)

    first =
      Instantflow.CollaborationFixtures.section_command(data, "application", %{
        "student_name" => "Primeiro"
      })

    second = %{first | "key" => "other-guardian", "values" => %{"student_name" => "Segundo"}}
    results = race(c, data.ticket.id, [{f.parent, first}, {other, second}])
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert {:error, :conflict} in results
    assert {:ok, final} = Instantflow.Enrollment.get(f.parent, f.enrollment.id)
    assert final.section_revision == 2
    assert count_receipts(data.ticket.id) == 2
  end

  test "guardian-link revocation commits before a queued parent mutation reauthorizes", c do
    f = enrollment_runtime(c)
    observer = self()
    supervisor = start_supervised!(Task.Supervisor)

    revoker =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Repo.put_dynamic_repo(c.runtime)

        Repo.transaction(fn ->
          result = Instantflow.Enrollment.verify(c.a_scope, f.link.id, false)
          send(observer, :guardian_gate_held)

          receive do
            :commit -> result
          after
            5000 -> Repo.rollback(:barrier_timeout)
          end
        end)
      end)

    assert_receive :guardian_gate_held, 5000

    command =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Repo.put_dynamic_repo(c.runtime)

        Instantflow.Enrollment.save(
          f.parent,
          f.enrollment.id,
          %{"student_name" => "Não deve salvar"},
          1,
          1,
          "revoked-guardian"
        )
      end)

    connection =
      start_supervised!(
        Supervisor.child_spec({Postgrex, c.owner_config ++ [database: c.database]},
          id: :guardian_observer
        )
      )

    assert wait_for_waiters(connection, c.database, 1, 1000)
    send(revoker.pid, :commit)
    assert {:ok, {:ok, _}} = Task.await(revoker)
    assert {:error, :not_found} = Task.await(command)
    assert count_receipts(f.enrollment.ticket_id) == 1
    assert Instantflow.Enrollment.list(f.parent) == []
  end

  defp enrollment_runtime(c) do
    departments =
      Map.new(~w(admissions academic finance it), &{&1 <> "_department", c.a_scope.department_id})

    {:ok, version} = Instantflow.Enrollment.install(c.a_scope, departments)

    {:ok, enrollment} =
      Instantflow.Enrollment.create(c.a_scope, version.workflow_id, Ecto.UUID.generate())

    {:ok, invitation} =
      Instantflow.Enrollment.invite(c.a_scope, enrollment.id, "parent#{c.a.id}@example.test")

    {:ok, user} =
      Identity.accept_invitation(invitation.token, %{
        "name" => "Responsável fictício",
        "password" => "fictional-password-123"
      })

    parent = Identity.scope(user.id, c.a.id)

    [link] =
      OperatorRepo.all(
        from g in Instantflow.Enrollment.GuardianLink, where: g.membership_id == ^parent.id
      )

    {:ok, _} = Instantflow.Enrollment.verify(c.a_scope, link.id, true)
    %{enrollment: enrollment, parent: parent, link: link}
  end

  defp collaborative_ticket(c, expected_version \\ 1) do
    bindings = %{
      "roles" => %{
        "requester" => ["admin", "staff"],
        "reviewer" => ["staff"],
        "finance" => ["finance"]
      },
      "departments" => %{"review_department" => c.a_scope.department_id}
    }

    {:ok, version} =
      WorkflowCatalog.publish(
        c.a_scope,
        Instantflow.CollaborationFixtures.collaborative_definition(),
        bindings,
        expected_version
      )

    {:ok, result} =
      WorkflowRuntime.command(c.a_scope, %{
        "operation" => "create",
        "key" => Ecto.UUID.generate(),
        "workflow_id" => version.workflow_id
      })

    {:ok, data} = WorkflowRuntime.get(c.a_scope, result["ticket_id"])
    {result["ticket_id"], data}
  end

  defp reviewer(c, suffix) do
    user =
      OperatorRepo.insert!(
        User.changeset(%User{email: "peer#{c.a.id}-#{suffix}@example.com"}, %{
          name: "Revisor",
          password: "fictional-password-123"
        })
      )

    OperatorRepo.insert!(%Membership{
      organization_id: c.a.id,
      user_id: user.id,
      department_id: c.a_scope.department_id,
      role: "staff"
    })

    Identity.scope(user.id, c.a.id)
  end

  defp count_receipts(id),
    do:
      OperatorRepo.aggregate(
        from(r in Instantflow.WorkflowRuntime.Receipt, where: r.ticket_id == ^id),
        :count
      )

  defp race(c, id, commands) do
    connection =
      start_supervised!(
        Supervisor.child_spec({Postgrex, c.owner_config ++ [database: c.database]},
          id: make_ref()
        )
      )

    Postgrex.query!(connection, "BEGIN")
    Postgrex.query!(connection, "SELECT id FROM tickets WHERE id=$1 FOR UPDATE", [id])
    supervisor = start_supervised!(Supervisor.child_spec(Task.Supervisor, id: make_ref()))

    tasks =
      Enum.map(commands, fn command ->
        Task.Supervisor.async_nolink(supervisor, fn ->
          Repo.put_dynamic_repo(c.runtime)

          {actor, value} =
            case command do
              {actor, value} -> {actor, value}
              value -> {c.a_scope, value}
            end

          WorkflowRuntime.command(actor, value)
        end)
      end)

    assert wait_for_waiters(connection, c.database, length(tasks), 1000)
    Postgrex.query!(connection, "COMMIT")
    Enum.map(tasks, &Task.await/1)
  end

  defp wait_for_waiters(_, _, _, 0), do: false

  defp wait_for_waiters(connection, database, expected, remaining) do
    [[count]] =
      Postgrex.query!(
        connection,
        "SELECT count(*) FROM pg_stat_activity WHERE datname=$1 AND usename='instantflow_runtime' AND wait_event_type='Lock'",
        [database]
      ).rows

    count >= expected or wait_for_waiters(connection, database, expected, remaining - 1)
  end
end
