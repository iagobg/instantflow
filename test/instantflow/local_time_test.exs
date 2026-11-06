defmodule Instantflow.LocalTimeTest do
  use Instantflow.DataCase, async: true

  test "formats UTC instants in São Paulo including the local date boundary" do
    assert Instantflow.LocalTime.format(~U[2026-10-20 01:30:00Z]) ==
             "19/10/2026 22:30 (São Paulo)"
  end

  test "operational dates and displayed instants use the configured timezone across midnight" do
    instant = ~U[2026-10-22 01:30:00Z]
    assert Instantflow.LocalTime.date("America/Sao_Paulo", instant) == ~D[2026-10-21]
    assert Instantflow.LocalTime.date("Asia/Tokyo", instant) == ~D[2026-10-22]

    assert Instantflow.LocalTime.format(instant, "Asia/Tokyo") ==
             "22/10/2026 10:30 (Asia/Tokyo)"
  end

  test "default operational date refreshes organization settings instead of a stale caller" do
    actor = Instantflow.IdentityFixtures.staff_fixture()

    actor.organization
    |> Ecto.Changeset.change(timezone: "Asia/Tokyo")
    |> Repo.update!()

    assert Instantflow.Operations.today(actor) == Instantflow.LocalTime.date("Asia/Tokyo")
  end

  test "formatting deduplicates instants and bounds each query without changing calendar labels" do
    alias Instantflow.{Diagnostics.QueryProbe, LocalTime}
    instants = for second <- 0..500, do: DateTime.add(~U[2026-10-20 01:30:00Z], second)

    {formatted, report} =
      QueryProbe.capture(fn -> LocalTime.format_instants(instants ++ instants) end)

    assert report.statements == 3
    assert map_size(formatted) == 501
    assert formatted[hd(instants)] == "19/10/2026 22:30 (São Paulo)"
    {empty, report} = QueryProbe.capture(fn -> LocalTime.format_instants([]) end)
    assert empty == %{}
    assert report.statements == 0

    {strings, report} =
      QueryProbe.capture(fn ->
        LocalTime.format_many(["2026-10-20T01:30:00Z"], "America/Sao_Paulo")
      end)

    assert strings["2026-10-20T01:30:00Z"] == "19/10/2026 22:30 (America/Sao_Paulo)"
    assert report.statements == 1
  end

  test "batch formatting keeps IANA daylight saving transitions and local date boundaries" do
    spring = [~U[2026-03-08 06:30:00Z], ~U[2026-03-08 07:30:00Z]]
    fall = [~U[2026-11-01 05:30:00Z], ~U[2026-11-01 06:30:00Z]]
    times = Instantflow.LocalTime.format_instants(spring ++ fall, "America/New_York")
    assert times[hd(spring)] == "08/03/2026 01:30 (America/New_York)"
    assert times[List.last(spring)] == "08/03/2026 03:30 (America/New_York)"
    assert times[hd(fall)] == "01/11/2026 01:30 (America/New_York)"
    assert times[List.last(fall)] == times[hd(fall)]

    assert Instantflow.LocalTime.format_instants([~U[2026-10-22 01:30:00Z]], "Asia/Tokyo") ==
             %{~U[2026-10-22 01:30:00Z] => "22/10/2026 10:30 (Asia/Tokyo)"}
  end
end
