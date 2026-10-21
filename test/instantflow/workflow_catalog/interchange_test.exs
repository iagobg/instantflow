defmodule Instantflow.WorkflowCatalog.InterchangeTest do
  use ExUnit.Case, async: true
  import Instantflow.WorkflowFixtures
  alias Instantflow.WorkflowCatalog.{Authoring, Definition, Interchange, Schema, Templates}

  test "delivered schema and semantic validator accept shipped examples and editor-created definitions" do
    for path <- Path.wildcard("design/examples/*.json") do
      assert {:ok, d} = path |> File.read!() |> Interchange.decode()
      assert :ok = Schema.validate(d)
      assert :ok = Definition.validate(d)
    end

    d = Templates.starter("office_approval", "Aprovação administrativa")

    {:ok, d} =
      Authoring.change(d, "fields", "request", nil, %{
        "key" => "amount",
        "label" => "Valor",
        "type" => "money",
        "currency" => "BRL"
      })

    {:ok, d} =
      Authoring.change(d, "stages", nil, "closed", %{
        "key" => "closed",
        "label" => "Encerrado",
        "initial" => "false",
        "terminal" => "true"
      })

    assert :ok = Schema.validate(d)
    assert :ok = Definition.validate(d)
    assert {:ok, ^d} = d |> Interchange.encode() |> Interchange.decode()
  end

  test "malformed JSON, duplicate keys, size and depth are rejected before semantic validation" do
    for json <- [
          "{",
          ~s({"name":"A","name":"B"}),
          ~s({"a":{"b":1,"b":2}}),
          String.duplicate("[", 21) <> String.duplicate("]", 21),
          String.duplicate(" ", 1_048_577)
        ] do
      assert {:error, :invalid_json} = Interchange.decode(json)
    end

    assert {:ok, %{"x" => "[{\\\"}"}} = Interchange.decode(~s({"x":"[{\\\\\\\"}"}))
  end

  test "unknown fields and executable capabilities fail at every supported extension point" do
    d = Map.put(definition_fixture(), "format_version", "1.0")

    for invalid <- [
          Map.put(d, "organization_id", 2),
          Map.put(d, "capabilities", ["core", "python"]),
          Map.put(d, "format_version", "2.0"),
          put_in(d, ["views", Access.at(0), "script"], "print(1)"),
          put_in(d, ["views", Access.at(0), "columns"], ["private.secret"]),
          put_in(d, ["sections", Access.at(0), "fields", Access.at(0), "secret"], "password"),
          put_in(d, ["transitions", Access.at(0), "actions"], [
            %{"type" => "python", "behavior" => "success"}
          ]),
          put_in(d, ["transitions", Access.at(0), "guard"], %{
            "op" => "present",
            "field" => "request.summary",
            "code" => "eval()"
          })
        ] do
      assert {:error, _} = Definition.validate(invalid)
    end
  end

  test "schema assertions stay within the evaluator's implemented vocabulary" do
    visit_schema(Schema.document())
  end

  defp visit_schema(schema) do
    supported =
      ~w($schema $id title description $defs type properties required additionalProperties minProperties maxProperties items minItems maxItems uniqueItems minLength maxLength minimum maximum pattern enum const anyOf $ref)

    assert Enum.all?(Map.keys(schema), &(&1 in supported))

    if schema["type"] == "object" do
      if is_map(schema["additionalProperties"]) do
        assert schema["minProperties"] == 1
        assert schema["maxProperties"] == 16
        visit_schema(schema["additionalProperties"])
      else
        assert schema["additionalProperties"] == false
        assert is_list(schema["required"])
        assert Enum.all?(schema["required"], &Map.has_key?(schema["properties"], &1))
      end
    end

    if schema["$ref"], do: assert(String.starts_with?(schema["$ref"], "#/$defs/"))
    for {_, child} <- schema["properties"] || %{}, do: visit_schema(child)
    for {_, child} <- schema["$defs"] || %{}, do: visit_schema(child)
    for child <- schema["anyOf"] || [], do: visit_schema(child)
    if schema["items"], do: visit_schema(schema["items"])
  end

  test "stable JSON ordering preserves every supported guard/action and ignores map insertion order" do
    d = Map.put(definition_fixture(), "format_version", "1.0")

    guard = %{
      "op" => "all",
      "args" => [
        %{"op" => "present", "field" => "request.summary"},
        %{
          "op" => "any",
          "args" => [
            %{"op" => "eq", "field" => "request.summary", "value" => "A"},
            %{"op" => "delivery_succeeded", "kind" => "simulate_notification"}
          ]
        }
      ]
    }

    d = put_in(d, ["transitions", Access.at(0), "guard"], guard)
    assert :ok = Definition.validate(d)
    assert {:ok, ^d} = d |> Interchange.encode() |> Interchange.decode()
    assert Interchange.digest(d) == Interchange.digest(d |> Enum.reverse() |> Map.new())
    item = hd(d["transitions"])

    params =
      Authoring.form(item, d)
      |> Ecto.Changeset.apply_changes()
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

    {:ok, changed} = Authoring.change(d, "transitions", nil, item["key"], params)
    assert hd(changed["transitions"])["guard"] == guard
    assert hd(changed["transitions"])["actions"] == item["actions"]
  end
end
