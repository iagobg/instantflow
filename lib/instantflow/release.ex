defmodule Instantflow.Release do
  @moduledoc "Operator-only commands invoked with bin/instantflow eval."

  def python_switch(enabled) when is_boolean(enabled) do
    Application.load(:instantflow)
    System.fetch_env!("OPERATOR_DATABASE_URL")

    {:ok, {:ok, _}, _} =
      Ecto.Migrator.with_repo(Instantflow.OperatorRepo, fn repo ->
        repo.transaction(fn ->
          repo.query!(
            "WITH changed AS (UPDATE calculation_switch SET enabled = $1, generation = generation + 1 WHERE id = 1 RETURNING enabled, generation) INSERT INTO calculation_switch_events (enabled, generation, operator, inserted_at) SELECT enabled, generation, current_user, now() FROM changed",
            [enabled]
          )
        end)
      end)

    :ok
  end

  def migrate do
    Application.load(:instantflow)
    System.fetch_env!("OPERATOR_DATABASE_URL")
    password = System.fetch_env!("RUNTIME_DB_PASSWORD")

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Instantflow.OperatorRepo, fn repo ->
        Ecto.Migrator.run(repo, :up, all: true)

        %{rows: [[sql]]} =
          repo.query!(
            "SELECT format('ALTER ROLE instantflow_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS PASSWORD %L', $1::text)",
            [password],
            log: false
          )

        repo.query!(sql, [], log: false)
      end)

    :ok
  end
end
