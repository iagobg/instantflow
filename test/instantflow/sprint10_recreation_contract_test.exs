defmodule Instantflow.Sprint10RecreationContractTest do
  use ExUnit.Case, async: true

  alias Instantflow.{
    Sprint10RecreationFixtures,
    WorkflowCatalog.Definition,
    WorkflowCatalog.Interchange
  }

  test "all independent school copies and equipment compose portable declared contracts" do
    for name <- ~w(enrollment incident requisition field_trip) do
      d = Sprint10RecreationFixtures.definition(name)
      assert :ok = Definition.validate(d), name
      assert {:ok, ^d} = d |> Interchange.encode() |> Interchange.decode()
      assert Enum.all?(d["sections"], &String.starts_with?(&1["key"], "copy_"))
      assert Enum.all?(d["stages"], &String.starts_with?(&1["key"], "copy_"))
      assert Enum.all?(d["role_requirements"], &String.starts_with?(&1["key"], "copy_"))
    end

    assert :ok = Definition.validate(Sprint10RecreationFixtures.equipment())

    assert :ok =
             Definition.validate(
               Map.put(
                 Sprint10RecreationFixtures.equipment(),
                 "capabilities",
                 ~w(core finance operations documents participants communications)
               )
             )
  end

  test "synthetic preview shares live policy without database access and rejects invalid selections" do
    d = Instantflow.BuilderFixtures.participant_page_definition()

    params = %{
      "page" => "my_packet",
      "role" => "visitor",
      "stage" => "draft",
      "verified" => "true"
    }

    preview = Instantflow.WorkflowRuntime.ParticipantPreview.project(d, params)
    assert preview.allowed?
    assert Enum.map(preview.fields, & &1.id) == ["customer_details.description"]
    assert preview.actions == ["Enviar documentação"]

    refute Instantflow.WorkflowRuntime.ParticipantPreview.project(
             d,
             Map.put(params, "verified", "false")
           ).allowed?

    refute Instantflow.WorkflowRuntime.ParticipantPreview.project(
             d,
             Map.put(params, "stage", %{})
           ).allowed?

    refute Instantflow.WorkflowRuntime.ParticipantPreview.project(
             d,
             Map.put(params, "role", "admin")
           ).allowed?
  end

  test "unsupported curated recipients, executable configuration and unknown targets fail actionably" do
    d = Instantflow.CuratedFixtures.definition()

    for bad <- [
          put_in(d, ["communications", Access.at(0), "fields"], ["request.missing"]),
          put_in(d, ["communications", Access.at(0), "recipient_relationship"], "unknown"),
          put_in(d, ["communications", Access.at(0), "release_actors"], [
            %{"role" => "visitor", "scope" => "participant", "relationship" => "claimant"}
          ]),
          update_in(
            d,
            ["communications", Access.at(0)],
            &Map.put(&1, "expression", "send_all()")
          ),
          put_in(d, ["transitions", Access.at(0), "guard", "communication"], "unknown"),
          Map.update!(d, "communications", &(&1 ++ &1))
        ] do
      assert {:error, [_ | _]} = Definition.validate(bad)
    end
  end
end
