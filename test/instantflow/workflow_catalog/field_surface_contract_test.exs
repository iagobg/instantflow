defmodule Instantflow.WorkflowCatalog.FieldSurfaceContractTest do
  use Instantflow.DataCase, async: true
  import Instantflow.IdentityFixtures
  alias Instantflow.BuilderFixtures

  alias Instantflow.WorkflowCatalog.{
    Authoring,
    Definition,
    Draft,
    Interchange,
    Schema,
    Templates,
    Version,
    Workflow
  }

  @scalar ~w(short_text long_text integer money date datetime boolean single_choice multiple_choice)
  @types @scalar ++ ~w(directory_reference attachment)
  @queryable ~w(short_text integer money date datetime boolean single_choice)

  test "schema, authoring and the maintained field/surface matrix have the same vocabulary" do
    schema_types =
      Schema.document()["$defs"]["field"]["anyOf"]
      |> Enum.flat_map(fn branch ->
        List.wrap(branch["properties"]["type"]["enum"] || branch["properties"]["type"]["const"])
      end)
      |> Enum.uniq()
      |> Enum.sort()

    assert schema_types == Enum.sort(@types)
    assert Enum.sort(Authoring.field_types()) == Enum.sort(@types)
  end

  for type <- @types do
    @field_type type
    test "#{type} portable declarations enforce the supported surface matrix" do
      d = definition(@field_type)
      assert :ok = Definition.validate(d)
      {:ok, decoded} = d |> Interchange.encode() |> Interchange.decode()
      assert decoded == d

      participant =
        put_in(d, ["interface", "pages", Access.at(1), "participant", "fields"], [
          "customer_details.value"
        ])

      check(participant, @field_type in @scalar, "interface.pages.my_packet.participant.fields")

      documents =
        put_in(d, ["interface", "pages", Access.at(1), "participant", "documents"], [
          "customer_details.value"
        ])

      check(
        documents,
        @field_type == "attachment",
        "interface.pages.my_packet.participant.documents"
      )

      communication =
        Map.put(d, "capabilities", d["capabilities"] ++ ["communications"])
        |> Map.put("communications", [notice()])

      check(communication, @field_type in @scalar, "communications.matrix_notice.fields")

      view = %{
        "key" => "matrix",
        "label" => "Matriz",
        "type" => "table",
        "columns" => ["stage", "customer_details.value"]
      }

      assert :ok = Definition.validate(Map.put(d, "views", [view]))

      check(
        Map.put(d, "views", [Map.put(view, "filters", ["customer_details.value"])]),
        @field_type in @queryable,
        "views.matrix"
      )

      check(
        Map.put(d, "views", [
          Map.put(view, "sort", %{"field" => "customer_details.value", "direction" => "asc"})
        ]),
        @field_type in @queryable,
        "views.matrix"
      )

      calendar =
        view |> Map.put("type", "calendar") |> Map.put("calendar_field", "customer_details.value")

      check(Map.put(d, "views", [calendar]), @field_type in ~w(date datetime), "views.matrix")

      if @field_type in @scalar do
        core =
          Templates.starter("ordinary_#{@field_type}", "Formulário básico")
          |> update_in(["sections", Access.at(0), "fields"], &(&1 ++ [field(@field_type)]))

        assert :ok = Definition.validate(core)
        assert core["capabilities"] == ["core"]
      end
    end
  end

  test "unsupported participant and message sources cannot enter through import or publication" do
    admin = staff_fixture()

    for type <- ~w(directory_reference attachment), surface <- [:participant, :message] do
      d = definition(type)

      invalid =
        case surface do
          :participant ->
            put_in(d, ["interface", "pages", Access.at(1), "participant", "fields"], [
              "customer_details.value"
            ])

          :message ->
            d
            |> Map.update!("capabilities", &(&1 ++ ["communications"]))
            |> Map.put("communications", [notice()])
        end

      before_workflows = Repo.aggregate(Workflow, :count)

      assert {:error, {:invalid_definition, errors}} =
               Templates.import(admin, Interchange.encode(invalid))

      assert errors != []
      assert Repo.aggregate(Workflow, :count) == before_workflows

      {:ok, draft} =
        Templates.import(admin, Interchange.encode(d), %{
          "template_key" => "rejected_#{surface}_#{type}"
        })

      invalid = Map.put(invalid, "template_key", draft.definition["template_key"])

      {:ok, saved} =
        Templates.save(admin, draft.id, draft.revision, invalid, %{
          "roles" => %{},
          "departments" => %{}
        })

      assert {:error, {:invalid_definition, ^errors}} =
               Templates.publish(admin, saved.id, saved.revision)

      assert Repo.get!(Draft, saved.id).published_version_id == nil
    end

    assert Repo.aggregate(Version, :count) == 0
  end

  defp check(d, allowed?, path) do
    assert :ok = Schema.validate(d)
    {:ok, decoded} = d |> Interchange.encode() |> Interchange.decode()
    assert Definition.validate(decoded) == Definition.validate(d)

    if allowed? do
      assert :ok = Definition.validate(d)
    else
      assert {:error, errors} = Definition.validate(d)
      assert Enum.any?(errors, &String.starts_with?(&1, path)), inspect(errors)
    end
  end

  defp definition(type) do
    BuilderFixtures.participant_page_definition()
    |> Map.put("template_key", "contract_#{type}")
    |> update_in(["sections", Access.at(1), "fields"], &(&1 ++ [field(type)]))
  end

  defp field(type) do
    base = %{"key" => "value", "label" => "Valor", "type" => type}

    case type do
      type when type in ~w(single_choice multiple_choice) ->
        Map.put(base, "options", ["A", "B"])

      "money" ->
        Map.put(base, "currency", "BRL")

      "directory_reference" ->
        Map.put(base, "reference", %{
          "target" => "participant",
          "relationship" => "claimant",
          "cardinality" => "one"
        })

      "attachment" ->
        policy =
          Definition.fields(BuilderFixtures.document_definition())["customer_details.evidence"][
            "document_policy"
          ]

        Map.put(base, "document_policy", policy)

      _ ->
        base
    end
  end

  defp notice do
    %{
      "key" => "matrix_notice",
      "label" => "Valor selecionado",
      "recipient_relationship" => "claimant",
      "fields" => ["customer_details.value"],
      "behavior" => "success",
      "release_actors" => [
        %{
          "role" => "reviewer",
          "scope" => "workflow_department",
          "department_binding" => "responsible"
        }
      ]
    }
  end
end
