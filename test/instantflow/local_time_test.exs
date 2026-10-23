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
end
