defmodule Instantflow.WorkflowCatalog.Diagnostics do
  @moduledoc "Pure, path-addressed publication errors shared by editor, import and direct publication."
  alias Instantflow.WorkflowCatalog.{CalculationContract, Capabilities, Definition, Interface}

  # Structural validation runs first. This boundary never queries tenant state.
  def validate(definition) do
    case errors(definition) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  def errors(d) do
    fields = Definition.fields(d)
    stages = Enum.map(d["stages"], & &1["key"])
    roles = Enum.map(d["role_requirements"], & &1["key"])

    creation = references(d["creation"]["roles"], roles, "modelo.creation.roles")

    transitions =
      d["transitions"]
      |> Enum.with_index()
      |> Enum.flat_map(fn {t, i} ->
        path = "modelo.transitions[#{i}]"

        references([t["from"]], stages, path <> ".from") ++
          references([t["to"]], stages, path <> ".to") ++
          references(t["required_fields"], Map.keys(fields), path <> ".required_fields") ++
          actor_errors(t["actors"], roles, d, path <> ".actors") ++
          finance_errors(t["finance"], d, fields, path <> ".finance") ++
          if(CalculationContract.spec?(t["calculation"], d),
            do: [],
            else: [path <> ".calculation: mapeamento de cálculo inválido."]
          )
      end)

    sections =
      d["sections"]
      |> Enum.with_index()
      |> Enum.flat_map(fn {s, i} ->
        path = "modelo.sections[#{i}].access"

        document_errors(s["fields"], d, roles, "modelo.sections[#{i}].fields") ++
          directory_errors(s["fields"], d, "modelo.sections[#{i}].fields") ++
          actor_errors(s["access"], roles, d, path) ++
          (s["access"]
           |> Enum.with_index()
           |> Enum.flat_map(fn {a, j} ->
             references(a["edit_stages"], stages, path <> "[#{j}].edit_stages")
           end))
      end)

    participants =
      Map.get(d, "participants", [])
      |> Enum.with_index()
      |> Enum.flat_map(fn {spec, i} ->
        path = "modelo.participants[#{i}].managers"

        candidate_errors(spec, roles, "modelo.participants[#{i}].candidate_roles") ++
          actor_errors(spec["managers"], roles, d, path) ++
          if(
            Enum.all?(
              spec["managers"],
              &(&1["scope"] in ~w(assigned_department workflow_department))
            ),
            do: [],
            else: [path <> ": use um departamento responsável explícito."]
          )
      end)

    capability =
      if Map.has_key?(d, "participants") and not Capabilities.enabled?(d, "participants"),
        do: ["modelo.participants: declare a capacidade participants."],
        else: []

    creation ++
      transitions ++ sections ++ participants ++ capability ++ interface_errors(d, roles)
  end

  defp candidate_errors(spec, roles, path) do
    case spec["candidate_roles"] do
      values when is_list(values) and values != [] -> references(values, roles, path)
      _ -> [path <> ": selecione os papéis elegíveis, sem conceder acesso ao registro."]
    end
  end

  defp references(values, allowed, path) do
    for value <- values,
        value not in allowed,
        do: "#{path}: referência não declarada #{inspect(value)}."
  end

  defp directory_errors(fields, d, path) do
    fields
    |> Enum.with_index()
    |> Enum.flat_map(fn {field, index} ->
      case field["reference"] do
        nil ->
          []

        spec ->
          definition =
            Enum.find(
              Map.get(d, "participants", []),
              &(&1["key"] == spec["relationship"])
            )

          cond do
            definition == nil ->
              [path <> "[#{index}].reference.relationship: relacionamento não declarado."]

            spec["target"] == "subject" and definition["kind"] != "subject" ->
              [
                path <>
                  "[#{index}].reference.target: selecione um relacionamento do tipo subject."
              ]

            true ->
              []
          end
      end
    end)
  end

  defp document_errors(fields, d, roles, path) do
    fields
    |> Enum.with_index()
    |> Enum.flat_map(fn {field, index} ->
      path = path <> "[#{index}].document_policy"

      case field["document_policy"] do
        nil ->
          if field["type"] == "attachment" and
               (Map.has_key?(d, "participants") or Capabilities.enabled?(d, "documents")),
             do: [path <> ": declare a política privada do campo."],
             else: []

        policy ->
          actor_errors(policy["reviewers"], roles, d, path <> ".reviewers") ++
            if(Capabilities.enabled?(d, "documents"),
              do: [],
              else: [path <> ": declare a capacidade documents."]
            ) ++
            if(
              Enum.all?(
                policy["reviewers"],
                &(&1["scope"] in ~w(assigned_department workflow_department assigned_user))
              ),
              do: [],
              else: [path <> ".reviewers: use um revisor interno com escopo explícito."]
            )
      end
    end)
  end

  defp actor_errors(actors, roles, d, path) do
    actors
    |> Enum.with_index()
    |> Enum.flat_map(fn {actor, i} ->
      references([actor["role"]], roles, path <> "[#{i}].role") ++
        if(actor["scope"] == "guardian" and Map.has_key?(d, "participants"),
          do: [path <> "[#{i}].scope: substitua guardian por um relacionamento declarado."],
          else: []
        ) ++
        if(actor["scope"] == "participant",
          do:
            references(
              [actor["relationship"]],
              Enum.map(Map.get(d, "participants", []), & &1["key"]),
              path <> "[#{i}].relationship"
            ),
          else: []
        ) ++
        if(actor["scope"] == "workflow_department",
          do:
            binding_reference(
              actor["department_binding"],
              "department",
              d,
              path <> "[#{i}].department_binding"
            ),
          else: []
        )
    end)
  end

  defp binding_reference(key, type, d, path) do
    allowed = for b <- d["bindings"], b["type"] == type, do: b["key"]
    references([key], allowed, path)
  end

  defp finance_errors(nil, _, _, _), do: []

  defp finance_errors(spec, d, fields, path) do
    if(Capabilities.enabled?(d, "finance"),
      do: [],
      else: [path <> ": declare a capacidade finance."]
    ) ++
      binding_reference(spec["account_binding"], "budget", d, path <> ".account_binding") ++
      Enum.flat_map(~w(amount_field quantity_field received_field), fn key ->
        if Map.has_key?(spec, key),
          do: references([spec[key]], Map.keys(fields), path <> "." <> key),
          else: []
      end)
  end

  defp interface_errors(d, roles) do
    pages = Interface.pages(d)

    blocks =
      pages
      |> Enum.with_index()
      |> Enum.flat_map(fn {page, i} ->
        for block <- page["blocks"],
            not Capabilities.enabled?(d, Interface.required_capability(block)),
            do:
              "modelo.interface.pages[#{i}].blocks: #{block} exige #{Interface.required_capability(block)}."
      end)

    access =
      (get_in(d, ["interface", "access"]) || %{})
      |> Enum.flat_map(fn {key, values} ->
        references(values, roles, "modelo.interface.access." <> key)
      end)

    blocks ++ access
  end
end
