defmodule Instantflow.Calculations.RunnerTest do
  use ExUnit.Case, async: false
  alias Instantflow.Calculations.Runner

  setup do
    previous =
      for key <- [
            :calculation_runner,
            :calculation_broker_url,
            :calculation_broker_token,
            :calculation_broker_socket
          ],
          into: %{},
          do: {key, Application.fetch_env(:instantflow, key)}

    Application.delete_env(:instantflow, :calculation_runner)
    Application.delete_env(:instantflow, :calculation_broker_socket)
    Application.put_env(:instantflow, :calculation_broker_token, String.duplicate("t", 32))

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, v} -> Application.put_env(:instantflow, key, v)
          :error -> Application.delete_env(:instantflow, key)
        end
      end
    end)

    :ok
  end

  defp broker(mode) do
    pid =
      start_supervised!(
        {Bandit,
         plug: {Instantflow.CalculationBroker, observer: self(), mode: mode},
         ip: {127, 0, 0, 1},
         port: 0,
         startup_log: false}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(pid)
    Application.put_env(:instantflow, :calculation_broker_url, "http://127.0.0.1:#{port}")
  end

  defp request,
    do: %{
      "organization_id" => 1,
      "run_id" => 10,
      "fence" => Ecto.UUID.generate(),
      "runtime" => String.duplicate("a", 64),
      "source" => "def calculate(x): return {'total': 1}",
      "input" => %{"synthetic" => 1}
    }

  test "broker requests authenticate and carry exact run identity, without application records" do
    broker(:ok)
    request = request()
    assert {:ok, %{"output" => %{"total" => 1}}} = Runner.execute(request)
    assert_receive {:broker_request, ^request, [authorization]}
    assert authorization == "Bearer " <> String.duplicate("t", 32)
  end

  test "wrong-tenant and oversized broker responses fail closed" do
    broker(:wrong_tenant)
    assert {:error, :runner_unavailable} = Runner.execute(request())
  end

  test "the HTTP runner refuses dispatch from inside a database transaction" do
    broker(:ok)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Instantflow.Repo)

    try do
      assert {:ok, {:error, :runner_unavailable}} =
               Instantflow.Repo.transaction(fn -> Runner.execute(request()) end)

      refute_receive {:broker_request, _, _}
    after
      Ecto.Adapters.SQL.Sandbox.checkin(Instantflow.Repo)
    end
  end

  test "container transport uses only the configured Unix socket" do
    path = Path.join(System.tmp_dir!(), "iflow-broker-#{System.unique_integer([:positive])}.sock")
    on_exit(fn -> File.rm(path) end)
    start_supervised!({Instantflow.UnixCalculationBroker, path: path, observer: self()})
    Application.put_env(:instantflow, :calculation_broker_socket, path)
    Application.put_env(:instantflow, :calculation_broker_url, "http://127.0.0.1:4010")
    request = request()
    assert {:ok, %{"output" => %{"total" => 1}}} = Runner.execute(request)
    assert_receive {:unix_request, ^request}
  end

  test "missing Unix socket cannot fall back to TCP" do
    broker(:ok)

    Application.put_env(
      :instantflow,
      :calculation_broker_socket,
      "/tmp/instantflow-nonexistent-broker.sock"
    )

    assert {:error, :runner_unavailable} = Runner.execute(request())
    refute_receive {:broker_request, _, _}
  end

  test "streaming enforces the response byte cap" do
    broker(:oversized)
    assert {:error, :runner_unavailable} = Runner.execute(request())
  end
end
