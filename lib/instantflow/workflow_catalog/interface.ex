defmodule Instantflow.WorkflowCatalog.Interface do
  @moduledoc "Pure interface contract: reusable block registry, terminology, pages and lifecycle validation."
  alias Instantflow.WorkflowCatalog.Capabilities

  @labels %{
    "resource" => "Recurso",
    "resources" => "Recursos",
    "catalog" => "Catálogo",
    "actor" => "Responsável",
    "destination" => "Destino"
  }
  @block_specs [
    {"records", "Registros e formulários", "core"},
    {"catalog", "Catálogo de itens", "operations"},
    {"resources", "Recursos e atendimentos", "operations"},
    {"items", "Entrada rápida de itens", "operations"},
    {"batches", "Lotes e entrega", "operations"},
    {"settlement", "Fechamento do atendimento", "operations"},
    {"daily_summary", "Resumo diário", "operations"},
    {"finance_setup", "Configuração financeira", "finance"},
    {"finance_summary", "Resumo financeiro autorizado", "finance"}
  ]
  @operational_blocks for {key, _, "operations"} <- @block_specs, do: key

  def blocks, do: Enum.map(@block_specs, &elem(&1, 0))
  def operational_blocks, do: @operational_blocks
  def block_label(block), do: @block_specs |> List.keyfind(block, 0) |> elem(1)
  def required_capability(block), do: @block_specs |> List.keyfind(block, 0) |> elem(2)
  def operational?(definition), do: Capabilities.enabled?(definition, "operations")

  def labels(definition),
    do: Map.merge(@labels, get_in(definition, ["interface", "labels"]) || %{})

  def pages(definition) do
    get_in(definition, ["interface", "pages"]) ||
      [
        %{
          "key" => "overview",
          "label" => "Acompanhamento",
          "blocks" => if(operational?(definition), do: @operational_blocks, else: ["records"])
        }
      ]
  end

  def close_transition(definition) do
    terminal = for s <- definition["stages"], s["terminal"], do: s["key"]

    get_in(definition, ["interface", "lifecycle", "close_transition"]) ||
      Enum.find_value(definition["transitions"], fn edge ->
        if edge["to"] in terminal, do: edge["key"]
      end)
  end

  def configuration(definition) do
    config =
      Map.merge(Map.get(definition, "interface", %{}), %{
        "pages" => pages(definition),
        "labels" => labels(definition)
      })

    if close_transition(definition),
      do: Map.put(config, "lifecycle", %{"close_transition" => close_transition(definition)}),
      else: config
  end

  def validate(definition) do
    config = definition["interface"]
    pages = pages(definition)
    keys = Enum.map(pages, & &1["key"])
    used = Enum.flat_map(pages, & &1["blocks"])
    edge = Enum.find(definition["transitions"], &(&1["key"] == close_transition(definition)))
    terminal = for s <- definition["stages"], s["terminal"], do: s["key"]

    roles = Enum.map(definition["role_requirements"], & &1["key"])

    access_roles =
      (get_in(definition, ["interface", "access"]) || %{}) |> Map.values() |> List.flatten()

    cond do
      Enum.any?(access_roles, &(&1 not in roles)) ->
        {:error, ["Os acessos dos blocos devem usar papéis declarados no processo."]}

      Enum.uniq(keys) != keys ->
        {:error, ["Cada página precisa de uma chave única."]}

      Enum.any?(used, &(!Capabilities.enabled?(definition, required_capability(&1)))) ->
        {:error, ["Os blocos de itens e recursos exigem o recurso operacional."]}

      operational?(definition) and (edge == nil or edge["to"] not in terminal) ->
        {:error,
         ["Selecione uma transição para uma etapa final como fechamento dos atendimentos."]}

      config && get_in(config, ["lifecycle", "close_transition"]) && edge == nil ->
        {:error, ["A transição de fechamento não existe neste processo."]}

      true ->
        :ok
    end
  end
end
