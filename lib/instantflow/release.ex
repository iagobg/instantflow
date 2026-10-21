defmodule Instantflow.Release do
  @moduledoc "Operator-only commands invoked with bin/instantflow eval."

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
