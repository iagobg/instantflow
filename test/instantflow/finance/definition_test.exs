defmodule Instantflow.Finance.DefinitionTest do
  use ExUnit.Case, async: true
  alias Instantflow.WorkflowCatalog.{Authoring, Definition, Interchange}

  test "finance templates validate and preserve effects through interchange and typed authoring" do
    for name <- ~w(requisition field_trip) do
      d =
        File.read!(Application.app_dir(:instantflow, "priv/workflows/#{name}.json"))
        |> Jason.decode!()

      assert :ok = Definition.validate(d)
      assert {:ok, ^d} = d |> Interchange.encode() |> Interchange.decode()

      for edge <- d["transitions"] do
        params =
          Authoring.form(edge, d)
          |> Ecto.Changeset.apply_changes()
          |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

        assert {:ok, updated} = Authoring.change(d, "transitions", nil, edge["key"], params)

        assert Enum.find(updated["transitions"], &(&1["key"] == edge["key"]))["finance"] ==
                 edge["finance"]

        assert :ok = Definition.validate(updated)
      end

      invalid =
        update_in(d["transitions"], fn edges ->
          Enum.map(edges, fn edge ->
            if edge["finance"],
              do: put_in(edge, ["finance", "account_binding"], "foreign"),
              else: edge
          end)
        end)

      assert {:error, _} = Definition.validate(invalid)
    end
  end
end
