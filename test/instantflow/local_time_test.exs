defmodule Instantflow.LocalTimeTest do
  use Instantflow.DataCase, async: true

  test "formats UTC instants in São Paulo including the local date boundary" do
    assert Instantflow.LocalTime.format(~U[2026-10-20 01:30:00Z]) ==
             "19/10/2026 22:30 (São Paulo)"
  end
end
