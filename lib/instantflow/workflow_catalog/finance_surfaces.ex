defmodule Instantflow.WorkflowCatalog.FinanceSurfaces do
  @moduledoc "Pure finance block binding and audience validation."
  def validate(d) do
    used = Instantflow.WorkflowCatalog.Interface.pages(d) |> Enum.flat_map(& &1["blocks"])
    spec = get_in(d, ["interface", "finance"])
    roles = Enum.map(d["role_requirements"], & &1["key"])
    budgets = for b <- d["bindings"], b["type"] == "budget", do: b["key"]

    cond do
      Enum.any?(used, &(&1 in ~w(finance_setup finance_summary))) && is_nil(spec) ->
        {:error, ["interface.finance: configure o vínculo de conta e a audiência."]}

      spec &&
          (spec["account_binding"] not in budgets or
             Enum.any?(spec["view_roles"], &(&1 not in roles))) ->
        {:error, ["interface.finance: revise os papéis declarados e o vínculo orçamentário."]}

      spec && not Instantflow.WorkflowCatalog.Capabilities.enabled?(d, "finance") ->
        {:error, ["interface.finance: habilite finance."]}

      true ->
        :ok
    end
  end
end
