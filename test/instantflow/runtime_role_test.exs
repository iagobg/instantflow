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
