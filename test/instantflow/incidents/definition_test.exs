defmodule Instantflow.IncidentsDefinitionTest do
  use ExUnit.Case, async: true
  alias Instantflow.WorkflowCatalog.{Authoring, Definition, Interchange}

  test "assignment constraints survive interchange and ordinary typed edits" do
    d =
      Application.app_dir(:instantflow, "priv/workflows/incident.json")
      |> File.read!()
      |> Jason.decode!()

    assert :ok = Definition.validate(d)
    assert {:ok, ^d} = d |> Interchange.encode() |> Interchange.decode()

    for section <- d["sections"] do
      params =
        Authoring.form(section, d)
        |> Ecto.Changeset.apply_changes()
        |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

      assert {:ok, updated} = Authoring.change(d, "sections", nil, section["key"], params)

      assert Enum.find(updated["sections"], &(&1["key"] == section["key"]))["assignment"] ==
               section["assignment"]

      assert :ok = Definition.validate(updated)

      for rule <- section["access"] do
        params =
          Authoring.form(rule, d)
          |> Ecto.Changeset.apply_changes()
          |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

        assert {:ok, updated} =
                 Authoring.change(
                   d,
                   "access",
                   section["key"],
                   Authoring.identity(rule, "access"),
                   params
                 )

        assert :ok = Definition.validate(updated)
      end
    end

    invalid =
      update_in(d["sections"], fn sections ->
        Enum.map(sections, fn section ->
          if section["key"] == "support",
            do: put_in(section, ["assignment", "role"], "foreign"),
            else: section
        end)
      end)

    assert {:error, _} = Definition.validate(invalid)
  end
end
