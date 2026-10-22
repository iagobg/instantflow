defmodule Instantflow.WorkflowCatalog.Bindings do
  @moduledoc """
  Resolves local installation mappings inside an authorized tenant transaction.

  Published mappings are immutable snapshots. Memberships, grants, relationship
  verification and suspension remain live and must be checked by each command.
  This module validates ownership only; it never grants access.
  """
  import Ecto.Query
  alias Instantflow.Repo
  alias Instantflow.Identity.Department
  alias Instantflow.Finance.Account

  def valid?(definition, bindings, organization_id, mode \\ :complete),
    do: errors(definition, bindings, organization_id, mode) == []

  def errors(definition, bindings, organization_id, mode \\ :complete)

  def errors(d, %{"roles" => roles, "departments" => departments} = bindings, org, mode)
      when is_map(roles) and is_map(departments) and mode in [:complete, :partial] do
    budgets = Map.get(bindings, "budgets", %{})

    unknown =
      for key <- Map.keys(bindings),
          key not in ~w(roles departments budgets),
          do: "mapeamentos.#{key}: grupo desconhecido."

    unknown ++
      group_errors(roles, Enum.map(d["role_requirements"], & &1["key"]), mode, "roles", fn list ->
        is_list(list) and list != [] and Enum.uniq(list) == list and
          Enum.all?(list, &(&1 in Instantflow.Access.binding_roles()))
      end) ++
      group_errors(departments, keys(d, "department"), mode, "departments", fn id ->
        is_integer(id) and
          Repo.exists?(
            from dep in Department,
              where: dep.id == ^id and dep.organization_id == ^org
          )
      end) ++
      group_errors(budgets, keys(d, "budget"), mode, "budgets", fn id ->
        is_integer(id) and
          Repo.exists?(
            from account in Account,
              where: account.id == ^id and account.organization_id == ^org
          )
      end)
  end

  def errors(_, _, _, _), do: ["mapeamentos: informe os grupos roles e departments."]

  defp keys(d, type), do: for(b <- d["bindings"], b["type"] == type, do: b["key"])

  defp group_errors(values, requirements, mode, group, valid?) when is_map(values) do
    missing =
      if mode == :complete do
        for key <- requirements,
            not Map.has_key?(values, key),
            do: "mapeamentos.#{group}.#{key}: selecione um mapeamento local."
      else
        []
      end

    missing ++
      Enum.flat_map(values, fn {key, value} ->
        cond do
          key not in requirements ->
            ["mapeamentos.#{group}.#{key}: referência não declarada."]

          not valid?.(value) ->
            ["mapeamentos.#{group}.#{key}: seleção inválida ou indisponível nesta organização."]

          true ->
            []
        end
      end)
  end

  defp group_errors(_, _, _, group, _), do: ["mapeamentos.#{group}: informe um objeto."]
end
