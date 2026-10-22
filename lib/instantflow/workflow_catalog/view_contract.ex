defmodule Instantflow.WorkflowCatalog.ViewContract do
  @moduledoc "Pure bounded configured view references and typed query declarations."
  alias Instantflow.WorkflowCatalog.Definition

  def validate(d) do
    fields = Definition.fields(d)
    roles = Enum.map(d["role_requirements"], & &1["key"])

    errors =
      Enum.flat_map(d["views"], fn v ->
        path = "views.#{v["key"]}"
        sort = v["sort"] && v["sort"]["field"]

        refs =
          (v["filters"] || []) ++
            List.wrap(v["calendar_field"]) ++
            List.wrap(v["urgency"] && v["urgency"]["field"]) ++
            if(sort in [nil, "id", "stage", "urgency"], do: [], else: [sort])

        section = Enum.find(d["sections"], &(&1["key"] == v["assignment_section"]))

        cond do
          Enum.any?(v["visibility_roles"] || [], &(&1 not in roles)) ->
            ["#{path}.visibility_roles: papel desconhecido."]

          Enum.any?(refs, &(not Map.has_key?(fields, &1))) ->
            ["#{path}: referência de campo desconhecida."]

          Enum.any?(
            refs,
            &(fields[&1]["type"] in ~w(attachment directory_reference multiple_choice long_text))
          ) ->
            ["#{path}: filtros/ordenação exigem campos escalares suportados."]

          v["calendar_field"] && fields[v["calendar_field"]]["type"] not in ~w(date datetime) ->
            ["#{path}.calendar_field: selecione uma data ou instante."]

          v["urgency"] &&
              (fields[v["urgency"]["field"]]["type"] != "single_choice" or
                 Enum.any?(
                   v["urgency"]["values"],
                   &(&1 not in fields[v["urgency"]["field"]]["options"])
                 )) ->
            ["#{path}.urgency: use opções do campo de escolha."]

          sort == "urgency" && is_nil(v["urgency"]) ->
            ["#{path}.sort: declare a urgência antes de ordenar por ela."]

          v["assignment_section"] && (is_nil(section) or is_nil(section["assignment"])) ->
            ["#{path}.assignment_section: selecione uma seção com atribuição nominal."]

          true ->
            []
        end
      end)

    if errors == [], do: :ok, else: {:error, errors}
  end
end
