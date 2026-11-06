defmodule Instantflow.Diagnostics.QueryProbeTest do
  use Instantflow.DataCase, async: false
  alias Instantflow.Diagnostics.QueryProbe
  @event [:instantflow, :repo, :query]

  test "counts decoded bytes and errors without retaining SQL, values or parameters" do
    probe = start_supervised!({QueryProbe, owner: self()})
    secret = "synthetic-private-value"
    Repo.query!("SELECT $1::text AS content, $2::jsonb AS details", [secret, %{"key" => "value"}])

    :telemetry.execute(@event, %{}, %{
      query: "SELECT secret",
      source: nil,
      result: {:error, :failed}
    })

    report = QueryProbe.finish(probe)
    assert report.statements == 2
    assert report.errors == 1
    assert report.rows == 1
    assert report.content_bytes == byte_size(secret)
    assert report.binary_bytes == byte_size(secret) + byte_size("keyvalue")
    assert report.content_selections == 1
    refute inspect(report) =~ secret
    refute inspect(report) =~ "SELECT"
    assert Enum.sort(Map.keys(report.groups)) == [:authorization, :documents, :history, :other]
    Repo.query!("SELECT 1")
    assert QueryProbe.finish(probe) == report
  end

  test "caller scope excludes other processes; all scope includes joined work" do
    supervisor = start_supervised!(Task.Supervisor)

    for {scope, expected} <- [caller: 1, all: 2] do
      {_, report} =
        QueryProbe.capture(
          fn ->
            Repo.query!("SELECT 1")
            supervisor |> Task.Supervisor.async(fn -> Repo.query!("SELECT 2") end) |> Task.await()
          end,
          scope: scope
        )

      assert report.statements == expected
    end
  end

  test "normal completion and exceptions detach temporary observers" do
    before = :telemetry.list_handlers(@event)
    assert {:ok, %{statements: 0}} = QueryProbe.capture(fn -> :ok end)
    assert_raise RuntimeError, "stop", fn -> QueryProbe.capture(fn -> raise "stop" end) end
    assert :telemetry.list_handlers(@event) == before
  end

  test "an aborted owner cannot leave its observer attached" do
    supervisor = start_supervised!(Task.Supervisor)
    owner = Task.Supervisor.async_nolink(supervisor, fn -> receive do: (:stop -> :ok) end)
    before = :telemetry.list_handlers(@event)
    probe = start_supervised!({QueryProbe, owner: owner.pid})
    ref = Process.monitor(probe)
    Task.Supervisor.terminate_child(supervisor, owner.pid)
    assert_receive {:DOWN, ^ref, :process, ^probe, :normal}
    assert :telemetry.list_handlers(@event) == before
  end
end
