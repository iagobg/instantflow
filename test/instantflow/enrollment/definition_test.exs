defmodule Instantflow.EnrollmentDefinitionTest do
  use ExUnit.Case, async: true
  alias Instantflow.WorkflowCatalog.{Authoring, Definition, Interchange}

  test "enrollment handoffs and guardian scopes survive ordinary typed authoring and interchange" do
    d =
      Application.app_dir(:instantflow, "priv/workflows/enrollment.json")
      |> File.read!()
      |> Jason.decode!()

    assert :ok = Definition.validate(d)
    assert {:ok, ^d} = d |> Interchange.encode() |> Interchange.decode()

    for item <- d["transitions"] do
      params =
        Authoring.form(item, d)
        |> Ecto.Changeset.apply_changes()
        |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

      assert {:ok, updated} = Authoring.change(d, "transitions", nil, item["key"], params)
      edge = Enum.find(updated["transitions"], &(&1["key"] == item["key"]))
      assert edge["actors"] == item["actors"]
      assert edge["department_binding"] == item["department_binding"]
      assert :ok = Definition.validate(updated)
    end

    section = hd(d["sections"])
    rule = Enum.find(section["access"], &(&1["scope"] == "workflow_department"))

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
    assert hd(updated["sections"])["access"] == section["access"]
  end

  test "unknown handoff departments and static operational attachment constants cannot publish" do
    d =
      Application.app_dir(:instantflow, "priv/workflows/enrollment.json")
      |> File.read!()
      |> Jason.decode!()

    invalid = put_in(d, ["transitions", Access.at(0), "department_binding"], "foreign_department")
    assert {:error, _} = Definition.validate(invalid)

    invalid =
      put_in(d, ["transitions", Access.at(0), "guard"], %{
        "op" => "eq",
        "field" => "application.document",
        "value" => Ecto.UUID.generate()
      })

    assert {:error, _} = Definition.validate(invalid)
  end
end
