defmodule Instantflow.RuntimeCase do
  @moduledoc "Independent runtime connections and a disposable database for committed race tests."
  use ExUnit.CaseTemplate
  alias Instantflow.{OperatorRepo, Repo}

  setup_all do
    config = OperatorRepo.config() |> Keyword.take([:username, :password, :hostname, :port])

    control =
      start_supervised!(
        Supervisor.child_spec({Postgrex, config ++ [database: "postgres"]}, id: :control)
      )

    database =
      "instantflow_concurrency_" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)

    Postgrex.query!(control, "CREATE DATABASE #{database} TEMPLATE template0 ENCODING 'UTF8'")

    on_exit(fn ->
      # The case supervisor has already stopped. This final connection removes
      # only the database successfully created by this case and always closes.
      {:ok, connection} = Postgrex.start_link(config ++ [database: "postgres"])

      try do
        Postgrex.query!(connection, "DROP DATABASE #{database} WITH (FORCE)")
      after
        GenServer.stop(connection)
      end
    end)

    owner =
      start_supervised!(
        {OperatorRepo, name: :independent_operator, database: database, pool_size: 2}
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
         name: :independent_runtime,
         database: database,
         username: "instantflow_runtime",
         password: System.get_env("RUNTIME_DB_PASSWORD", "instantflow-runtime-local-only"),
         pool: DBConnection.ConnectionPool,
         pool_size: 8}
      )

    %{owner: owner, runtime: runtime, database: database, owner_config: config}
  end

  setup context do
    OperatorRepo.put_dynamic_repo(context.owner)
    Repo.put_dynamic_repo(context.runtime)
    :ok
  end
end
