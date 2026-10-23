defmodule Instantflow.Sprint11AcceptanceFixtures do
  @moduledoc "Independent six-process acceptance definitions and explicit local mappings."
  alias Instantflow.{BuilderFixtures, Sprint10RecreationFixtures}

  def definitions do
    school =
      Enum.map(
        ~w(enrollment incident requisition field_trip),
        &Sprint10RecreationFixtures.definition/1
      )

    restaurant =
      File.read!(Path.expand("test/fixtures/sprint11/supper_room.json")) |> Jason.decode!()

    school ++ [restaurant, Sprint10RecreationFixtures.equipment()]
  end

  def bindings(actor, definition, account, role) do
    external = definition |> Map.get("participants", []) |> Enum.flat_map(& &1["candidate_roles"])

    %{
      "roles" =>
        Map.new(definition["role_requirements"], fn r ->
          {r["key"], [if(r["key"] in external, do: "external", else: role)]}
        end),
      "departments" =>
        Map.new(
          Enum.filter(definition["bindings"], &(&1["type"] == "department")),
          &{&1["key"], actor.department_id}
        ),
      "budgets" =>
        Map.new(
          Enum.filter(definition["bindings"], &(&1["type"] == "budget")),
          &{&1["key"], account}
        )
    }
  end

  def install(actor, account, role) do
    Enum.map(definitions(), fn d ->
      BuilderFixtures.install(actor, d, bindings(actor, d, account, role))
    end)
  end
end
