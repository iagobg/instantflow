defmodule Instantflow.ProcessMigrationTest do
  use ExUnit.Case, async: false
  alias Instantflow.{OperatorRepo, Repo, Identity, Operations}
  alias Instantflow.Identity.{Organization, Department, User, Membership}
  alias Instantflow.WorkflowCatalog.{Workflow, Version}

  test "forward migration preserves operational snapshots, pinned versions and menus created before the first visit" do
    config = OperatorRepo.config() |> Keyword.take([:username, :password, :hostname, :port])

    control =
      start_supervised!(
        Supervisor.child_spec({Postgrex, config ++ [database: "postgres"]},
          id: :migration_control
        )
      )

    database = "instantflow_process_migration_#{System.unique_integer([:positive])}"
    Postgrex.query!(control, "CREATE DATABASE #{database} TEMPLATE template0 ENCODING 'UTF8'")

    owner =
      start_supervised!(
        {OperatorRepo, [name: :process_migration_owner, database: database, pool_size: 2]}
      )

    OperatorRepo.put_dynamic_repo(owner)
    migrations = Application.app_dir(:instantflow, "priv/repo/migrations")
    migrate(migrations, to: 20_261_021_190_401, log: false)
    Instantflow.HistoricalSchema.prepare_seed()

    runtime =
      start_supervised!(
        {Repo,
         [
           name: :process_migration_runtime,
           database: database,
           username: "instantflow_runtime",
           password: System.get_env("RUNTIME_DB_PASSWORD", "instantflow-runtime-local-only"),
           pool: DBConnection.ConnectionPool,
           pool_size: 2
         ]}
      )

    Repo.put_dynamic_repo(runtime)

    try do
      a = OperatorRepo.insert!(%Organization{slug: "legacy-orders", name: "Legado fictício"})
      b = OperatorRepo.insert!(%Organization{slug: "menu-only", name: "Catálogo fictício"})
      da = OperatorRepo.insert!(%Department{organization_id: a.id, name: "Operação"})
      db = OperatorRepo.insert!(%Department{organization_id: b.id, name: "Operação"})

      user =
        OperatorRepo.insert!(
          User.changeset(%User{email: "migration@example.test"}, %{
            name: "Operador fictício",
            password: "migration-fictional-only"
          })
        )

      for {org, department} <- [{a, da}, {b, db}],
          do:
            OperatorRepo.insert!(%Membership{
              organization_id: org.id,
              department_id: department.id,
              user_id: user.id,
              role: "admin"
            })

      workflow =
        OperatorRepo.insert!(%Workflow{
          organization_id: a.id,
          key: "resource_service",
          name: "Atendimento legado"
        })

      definition =
        Application.app_dir(:instantflow, "priv/workflows/resource_service.json")
        |> File.read!()
        |> Jason.decode!()
        |> Map.delete("interface")
        |> Map.put("capabilities", ["core"])

      version =
        OperatorRepo.insert!(%Version{
          organization_id: a.id,
          workflow_id: workflow.id,
          number: 1,
          definition: definition,
          bindings: %{
            "roles" => %{"operator" => ["admin"]},
            "departments" => %{"service_department" => da.id}
          },
          published_by_id: user.id
        })

      actor = Identity.scope(user.id, a.id)

      {:ok, ticket} =
        Instantflow.WorkflowRuntime.command(
          actor,
          %{"operation" => "create", "key" => "legacy-ticket", "workflow_id" => workflow.id},
          :operations
        )

      insert = fn statement, values ->
        OperatorRepo.query!(statement, values).rows |> hd() |> hd()
      end

      resource =
        insert.(
          "INSERT INTO service_resources(organization_id,name) VALUES($1,'Mesa 08') RETURNING id",
          [a.id]
        )

      product =
        insert.(
          "INSERT INTO catalog_products(organization_id,name,category,price,destination,active,revision) VALUES($1,'Água mineral','Bebidas',600,'Balcão',true,1) RETURNING id",
          [a.id]
        )

      visit =
        insert.(
          "INSERT INTO service_sessions(organization_id,resource_id,ticket_id,resource_name,waiter,business_date,status,total,opened_at) VALUES($1,$2,$3,'Mesa 08','Carlos',CURRENT_DATE,'open',0,now()) RETURNING id",
          [a.id, resource, ticket["ticket_id"]]
        )

      batch =
        insert.(
          "INSERT INTO fulfillment_batches(organization_id,session_id,destination,kind,status,waiter,print_count,inserted_at) VALUES($1,$2,'Balcão','order','pending','Carlos',1,now()) RETURNING id",
          [a.id, visit]
        )

      insert.(
        "INSERT INTO fulfillment_lines(organization_id,batch_id,product_id,name,unit_price,quantity,notes) VALUES($1,$2,$3,'Água mineral',600,2,'Sem gelo') RETURNING id",
        [a.id, batch, product]
      )

      insert.(
        "INSERT INTO operation_receipts(organization_id,actor_id,key,operation,digest,result,inserted_at) VALUES($1,$2,'legacy','submit_batch',$3,$4,now()) RETURNING id",
        [a.id, user.id, :crypto.hash(:sha256, "legacy"), %{"ids" => [batch]}]
      )

      insert.(
        "INSERT INTO operation_day_closes(organization_id,business_date,actor_id,summary,inserted_at) VALUES($1,CURRENT_DATE - 1,$2,$3,now()) RETURNING id",
        [a.id, user.id, %{"sales" => 0}]
      )

      insert.(
        "INSERT INTO catalog_products(organization_id,name,category,price,destination,active,revision) VALUES($1,'Sopa','Entradas',2550,'Cozinha',true,1) RETURNING id",
        [b.id]
      )

      tables =
        ~w(catalog_products service_resources service_sessions fulfillment_batches fulfillment_lines operation_receipts operation_day_closes)

      before =
        Map.new(
          tables,
          &{&1, OperatorRepo.query!("SELECT to_jsonb(t) FROM #{&1} t ORDER BY id").rows}
        )

      Instantflow.HistoricalSchema.finish_seed()
      migrate(migrations, all: true, log: false)
      assert :ok = Instantflow.HistoricalSchema.assert_defaults()

      for table <- tables do
        expected =
          if table in ~w(service_sessions fulfillment_batches) do
            Enum.map(before[table], fn [row] -> [Map.put(row, "status", "archived")] end)
          else
            before[table]
          end

        assert OperatorRepo.query!(
                 "SELECT to_jsonb(t) - 'workflow_id' FROM #{table} t ORDER BY id"
               ).rows == expected
      end

      assert OperatorRepo.get!(Version, version.id).definition == definition

      assert OperatorRepo.get!(Instantflow.WorkflowRuntime.Ticket, ticket["ticket_id"]).workflow_version_id ==
               version.id

      data = Operations.workspace(actor, Operations.today(actor))
      assert hd(data.products).price == 600
      assert Operations.visit(actor, visit).total == 1200
      assert Operations.visit(actor, visit).archived?
      assert data.report.archived_count == 1
      assert data.report.archived_total == 1200
      assert data.sessions == []
      second = Operations.workspace(Identity.scope(user.id, b.id), Operations.today(actor))
      assert hd(second.products).name == "Sopa"
      assert second.version.definition["interface"]["pages"] != []
    after
      stop_supervised(Repo)
      stop_supervised(OperatorRepo)
      Postgrex.query!(control, "DROP DATABASE #{database} WITH (FORCE)")
    end
  end

  defp migrate(path, options) do
    previous = Code.compiler_options()
    Code.compiler_options(ignore_module_conflict: true)

    try do
      Ecto.Migrator.run(OperatorRepo, path, :up, options)
    after
      Code.compiler_options(previous)
    end
  end
end
