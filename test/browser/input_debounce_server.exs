# Run after migrating a disposable MIX_TEST_PARTITION=_input_* database:
# MIX_ENV=test mix run --no-start test/browser/input_debounce_server.exs
alias Instantflow.{Repo, WorkflowFixtures}

config = Application.fetch_env!(:instantflow, Repo)

unless String.starts_with?(config[:database], "instantflow_test_input_"),
  do: raise("Browser fixtures require a disposable instantflow_test_input_* database")

Application.put_env(:instantflow, Repo, Keyword.put(config, :pool, DBConnection.ConnectionPool))
Application.put_env(:instantflow, :delivery_worker, true)

endpoint =
  Application.fetch_env!(:instantflow, InstantflowWeb.Endpoint)
  |> Keyword.merge(
    server: true,
    code_reloader: false,
    watchers: [],
    http: [ip: {127, 0, 0, 1}, port: 4011],
    check_origin: ["//127.0.0.1:4011"]
  )

Application.put_env(:instantflow, InstantflowWeb.Endpoint, endpoint)
{:ok, _} = Application.ensure_all_started(:instantflow)
f = WorkflowFixtures.workflow_fixture()

records =
  Map.new(~w(typing immediate reason conflict reconnect), fn key ->
    id = WorkflowFixtures.create_ticket(f)
    {:ok, _} = WorkflowFixtures.save(f.requester, id, WorkflowFixtures.values())
    {key, id}
  end)

File.write!(
  Path.expand("../../.local/input-debounce-fixture.json", __DIR__),
  Jason.encode!(%{email: f.requester.user.email, records: records})
)

IO.puts("Input debounce fixture ready at http://127.0.0.1:4011")
receive do: (:stop -> :ok)
