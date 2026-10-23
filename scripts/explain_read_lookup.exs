alias Instantflow.{Repo, Identity, Tenant}

for key <- [:delivery_worker, :calculation_worker, :calculation_execution],
    do: Application.put_env(:instantflow, key, false)

{:ok, _} = Application.ensure_all_started(:instantflow)
report = File.read!(System.fetch_env!("READ_EXPLAIN_REPORT")) |> Jason.decode!()

{:ok, runtime} =
  Repo.start_link(
    name: :read_explain_runtime,
    database: report["database"],
    username: "instantflow_runtime",
    password: System.get_env("RUNTIME_DB_PASSWORD", "instantflow-runtime-local-only"),
    pool: DBConnection.ConnectionPool,
    pool_size: 2
  )

Repo.put_dynamic_repo(runtime)
actor = Identity.scope(1, 1)
pid = self()

:telemetry.attach(
  "capture-version-query",
  [:instantflow, :repo, :query],
  fn _, _, metadata, _ ->
    if self() == pid and metadata[:source] == "workflow_versions",
      do: Process.put(:version_query, {metadata.query, metadata.params})
  end,
  nil
)

_ = Instantflow.WorkflowCatalog.Views.search(actor, 1, "requests")
:telemetry.detach("capture-version-query")
{sql, params} = Process.get(:version_query)

plan =
  Tenant.read(actor, fn _ ->
    Repo.query!("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) " <> sql, params).rows
  end)

File.write!(
  System.fetch_env!("READ_EXPLAIN_OUTPUT"),
  Jason.encode!(%{database: report["database"], plan: plan}, pretty: true)
)

IO.puts(Jason.encode!(plan, pretty: true))
