defmodule Instantflow.WorkflowCatalog.Communications do
  @moduledoc "Portable curated release declarations; selection never grants recipient record access."
  alias Instantflow.WorkflowCatalog.{Capabilities, Definition}
  def specs(d), do: Map.get(d, "communications", [])
  def find(d, key), do: Enum.find(specs(d), &(&1["key"] == key))

  def validate(d) do
    fields = Definition.fields(d)
    roles = Enum.map(d["role_requirements"], & &1["key"])
    relationships = Enum.map(Map.get(d, "participants", []), & &1["key"])

    errors =
      Enum.flat_map(specs(d), fn spec ->
        path = "communications.#{spec["key"]}"

        cond do
          not Capabilities.enabled?(d, "communications") or
              not Capabilities.enabled?(d, "participants") ->
            ["#{path}: habilite communications e participants."]

          spec["recipient_relationship"] not in relationships ->
            ["#{path}.recipient_relationship: vínculo desconhecido."]

          Enum.any?(spec["fields"], &(not Map.has_key?(fields, &1))) ->
            ["#{path}.fields: campo desconhecido."]

          Enum.any?(spec["fields"], &(fields[&1]["type"] in ~w(attachment directory_reference))) ->
            ["#{path}.fields: selecione conteúdo escalar, não arquivos/referências locais."]

          Enum.any?(
            spec["release_actors"],
            &(&1["scope"] not in ~w(workflow_department assigned_department assigned_user) or
                  not Definition.valid_actor?(&1, roles, d))
          ) ->
            ["#{path}.release_actors: use atores internos explicitamente autorizados."]

          true ->
            []
        end
      end)

    keys = Enum.map(specs(d), & &1["key"])

    errors =
      if length(keys) == length(Enum.uniq(keys)),
        do: errors,
        else: errors ++ ["communications.key: use chaves únicas."]

    guard_keys = Enum.flat_map(d["transitions"], &guard_keys(&1["guard"]))

    errors =
      errors ++
        if(Enum.any?(guard_keys, &(&1 not in keys)),
          do: ["transitions.guard.communication: comunicação desconhecida."],
          else: []
        )

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp guard_keys(%{"op" => "communication_succeeded", "communication" => key}), do: [key]
  defp guard_keys(%{"args" => args}), do: Enum.flat_map(args, &guard_keys/1)
  defp guard_keys(_), do: []
end
