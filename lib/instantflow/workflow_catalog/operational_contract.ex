defmodule Instantflow.WorkflowCatalog.OperationalContract do
  @moduledoc "Explicit versioned operational semantics for supported builder definitions."
  alias Instantflow.WorkflowCatalog.Capabilities

  @v1 %{
    "version" => 1,
    "actor" => "captured_name",
    "settlement" => "full_manual",
    "reporting_timezone" => "organization",
    "currency" => "BRL",
    "payment_methods" => ~w(cash card pix),
    "consumption" => "estimated_product_units"
  }

  def defaults, do: @v1
  def resolve(definition), do: get_in(definition, ["interface", "operations"])

  def payment_options(definition) do
    labels = %{"cash" => "Dinheiro", "card" => "Cartão", "pix" => "Pix"}
    Enum.map((resolve(definition) || %{})["payment_methods"] || [], &{labels[&1], &1})
  end

  def validate(definition) do
    contract = get_in(definition, ["interface", "operations"])

    cond do
      is_nil(contract) and Capabilities.enabled?(definition, "operations") ->
        {:error, ["interface.operations: declare o contrato operacional versionado."]}

      is_nil(contract) ->
        :ok

      is_nil(get_in(definition, ["interface", "lifecycle", "close_transition"])) ->
        {:error,
         [
           "interface.lifecycle.close_transition: selecione o fechamento operacional explicitamente."
         ]}

      not Capabilities.enabled?(definition, "operations") ->
        {:error, ["interface.operations: exige a capacidade operations."]}

      Map.drop(contract, ["payment_methods"]) != Map.drop(@v1, ["payment_methods"]) ->
        {:error, ["interface.operations: contrato operacional não suportado na versão 1."]}

      not is_list(contract["payment_methods"]) or contract["payment_methods"] == [] or
        Enum.uniq(contract["payment_methods"]) != contract["payment_methods"] or
          Enum.any?(contract["payment_methods"], &(&1 not in @v1["payment_methods"])) ->
        {:error, ["interface.operations.payment_methods: selecione dinheiro, cartão ou Pix."]}

      true ->
        :ok
    end
  end
end
