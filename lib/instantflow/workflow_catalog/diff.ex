defmodule Instantflow.WorkflowCatalog.Diff do
  @moduledoc "Deterministic structural comparisons; keyed lists are compared by symbolic identity."

  def compare(before, after_value, path \\ "modelo")
  def compare(same, same, _), do: []

  def compare(before, after_value, path) when is_map(before) and is_map(after_value) do
    (Map.keys(before) ++ Map.keys(after_value))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(fn key ->
      compare(Map.get(before, key), Map.get(after_value, key), path <> "." <> key)
    end)
  end

  def compare(before, after_value, path) when is_list(before) and is_list(after_value) do
    if Enum.all?(before ++ after_value, &(is_map(&1) and is_binary(&1["key"]))) do
      changes =
        compare(Map.new(before, &{&1["key"], &1}), Map.new(after_value, &{&1["key"], &1}), path)

      if Enum.map(before, & &1["key"]) != Enum.map(after_value, & &1["key"]),
        do:
          changes ++
            [
              %{
                path: path <> ".ordem",
                before: Enum.map(before, & &1["key"]),
                after: Enum.map(after_value, & &1["key"])
              }
            ],
        else: changes
    else
      [%{path: path, before: before, after: after_value}]
    end
  end

  def compare(before, after_value, path), do: [%{path: path, before: before, after: after_value}]
end
