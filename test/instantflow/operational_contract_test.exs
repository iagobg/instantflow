defmodule Instantflow.OperationalContractTest do
  use ExUnit.Case, async: true
  alias Instantflow.WorkflowCatalog.{Definition, Interchange, OperationalContract}

  defp definition do
    File.read!(Path.expand("../fixtures/sprint11/supper_room.json", __DIR__)) |> Jason.decode!()
  end

  test "explicit contracts survive portable roundtrips and missing declarations cannot publish" do
    explicit = definition()
    assert :ok = Definition.validate(explicit)
    assert {:ok, ^explicit} = explicit |> Interchange.encode() |> Interchange.decode()
    legacy = update_in(explicit, ["interface"], &Map.delete(&1, "operations"))
    assert {:error, _} = Definition.validate(legacy)
    assert OperationalContract.resolve(legacy) == nil
  end

  test "unsupported accounting semantics, versions and payment combinations fail validation" do
    for {key, value} <- [
          {"currency", "USD"},
          {"settlement", "split"},
          {"actor", "account"},
          {"reporting_timezone", "UTC"},
          {"consumption", "stock"},
          {"version", 2},
          {"payment_methods", []},
          {"payment_methods", ["pix", "pix"]},
          {"payment_methods", ["refund"]}
        ] do
      invalid = put_in(definition(), ["interface", "operations", key], value)
      assert {:error, _} = Definition.validate(invalid)
    end

    core = Map.put(definition(), "capabilities", ["core"])
    assert {:error, _} = OperationalContract.validate(core)
  end
end
