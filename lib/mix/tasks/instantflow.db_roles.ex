defmodule Mix.Tasks.Instantflow.DbRoles do
  use Mix.Task
  @shortdoc "Configure the non-owner runtime role using operator credentials"
  def run(_) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, pid} = Instantflow.OperatorRepo.start_link()

    password =
      System.get_env("RUNTIME_DB_PASSWORD") ||
        if(Mix.env() != :prod,
          do: "instantflow-runtime-local-only",
          else: raise("RUNTIME_DB_PASSWORD required")
        )

    # Quoted by PostgreSQL itself; credentials never enter logs or source-controlled SQL.
    %{rows: [[sql]]} =
      Instantflow.OperatorRepo.query!(
        "SELECT format('ALTER ROLE instantflow_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS PASSWORD %L', $1::text)",
        [password],
        log: false
      )

    Instantflow.OperatorRepo.query!(sql, [], log: false)
    GenServer.stop(pid)
  end
end
