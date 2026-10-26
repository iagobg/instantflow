defmodule InstantflowWeb.RecordNavigation do
  @moduledoc "Bounded navigation hints. Runtime owners reauthorize every restored query."
  use InstantflowWeb, :verified_routes

  def context(value) when is_map(value) do
    scalar(value, ~w(view page_key view_page))
    |> Map.put("filters", filters(value["filters"]))
    |> Enum.reject(fn {_, v} -> v in ["", %{}] end)
    |> Map.new()
  end

  def context(_), do: %{}

  def filters(value) when is_map(value) do
    scalar(value, ~w(query stage assigned_to version_id page columns_page version_page))
    |> put_nested("fields", value["fields"], 20)
    |> put_nested("column_pages", value["column_pages"], 10)
  end

  def filters(_), do: %{}

  def with_context(path, context) when context == %{}, do: path

  def with_context(path, context),
    do: path <> "?" <> Plug.Conn.Query.encode(%{"context" => context(context)})

  def process_path(scope, workflow_id, context) do
    path =
      case context["page_key"] do
        nil -> ~p"/o/#{scope.organization.slug}/processos/#{workflow_id}"
        page -> ~p"/o/#{scope.organization.slug}/processos/#{workflow_id}/p/#{page}"
      end

    with_context(path, context)
  end

  defp scalar(value, keys) do
    for key <- keys,
        item = value[key],
        is_binary(item) or is_integer(item),
        text = to_string(item),
        byte_size(text) <= 500,
        into: %{},
        do: {key, text}
  end

  defp put_nested(result, key, value, limit) when is_map(value) do
    values =
      value
      |> Enum.filter(fn {k, v} ->
        is_binary(k) and byte_size(k) <= 100 and (is_binary(v) or is_integer(v))
      end)
      |> Enum.sort()
      |> Enum.take(limit)
      |> Map.new()
      |> then(&scalar(&1, Map.keys(&1)))

    if values == %{}, do: result, else: Map.put(result, key, values)
  end

  defp put_nested(result, _, _, _), do: result
end
