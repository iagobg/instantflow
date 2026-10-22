defmodule Instantflow.WorkflowCatalog.ParticipantPages do
  @moduledoc "Pure, bounded participant page declarations; visibility never grants record authority."
  alias Instantflow.WorkflowCatalog.{Capabilities, Definition, Interface}

  def pages(definition),
    do: Enum.filter(Interface.pages(definition), &Map.has_key?(&1, "participant"))

  def find(definition, key), do: Enum.find(pages(definition), &(&1["key"] == key))

  def validate(definition) do
    fields = Definition.fields(definition)
    roles = Enum.map(definition["role_requirements"], & &1["key"])
    actions = Enum.map(definition["transitions"], & &1["key"])

    errors =
      Enum.flat_map(pages(definition), fn page ->
        spec = page["participant"]
        path = "interface.pages.#{page["key"]}.participant"

        cond do
          not Capabilities.enabled?(definition, "participants") ->
            ["#{path}: habilite participantes."]

          page["blocks"] != ["records"] ->
            ["#{path}: a página de participação usa somente o bloco de registros."]

          Enum.any?(spec["visibility_roles"], &(&1 not in roles)) ->
            ["#{path}.visibility_roles: selecione papéis declarados."]

          Enum.any?(
            spec["audience"],
            &(&1["scope"] == "guardian" or not Definition.valid_actor?(&1, roles, definition))
          ) ->
            ["#{path}.audience: revise os papéis, escopos e vínculos declarados."]

          Enum.any?(spec["fields"] ++ spec["documents"], &(not Map.has_key?(fields, &1))) ->
            ["#{path}: selecione campos existentes."]

          Enum.any?(spec["fields"], &(fields[&1]["type"] in ~w(attachment directory_reference))) ->
            [
              "#{path}.fields: anexos usam documentos; referências de diretório ainda não são suportadas nesta página."
            ]

          Enum.any?(
            spec["documents"],
            &(fields[&1]["type"] != "attachment" or is_nil(fields[&1]["document_policy"]))
          ) ->
            ["#{path}.documents: selecione anexos com política de documentos declarada."]

          Enum.any?(spec["actions"], &(&1 not in actions)) ->
            ["#{path}.actions: selecione transições existentes."]

          Enum.any?(
            spec["messages"] || [],
            &is_nil(Instantflow.WorkflowCatalog.Communications.find(definition, &1))
          ) ->
            ["#{path}.messages: selecione comunicações declaradas."]

          true ->
            []
        end
      end)

    if errors == [], do: :ok, else: {:error, errors}
  end
end
