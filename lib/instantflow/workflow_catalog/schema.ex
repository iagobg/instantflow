defmodule Instantflow.WorkflowCatalog.Schema do
  @moduledoc "Structural validator driven by the shipped schema's deliberately small vocabulary."
  @external_resource Path.expand("../../../priv/templates/workflow-1.0.schema.json", __DIR__)
  @schema @external_resource |> File.read!() |> Jason.decode!()

  def document, do: @schema

  def validate(value) do
    case check(value, @schema, "modelo") do
      :ok ->
        :ok

      {:error, path} ->
        {:error, ["Estrutura inválida em #{path}; consulte o esquema da versão 1.0."]}
    end
  end

  defp check(value, %{"$ref" => "#/$defs/" <> key}, path),
    do: check(value, @schema["$defs"][key], path)

  defp check(value, %{"anyOf" => schemas}, path) do
    if Enum.any?(schemas, &(check(value, &1, path) == :ok)), do: :ok, else: {:error, path}
  end

  defp check(value, schema, path) do
    valid =
      (not Map.has_key?(schema, "const") or value == schema["const"]) and
        (not Map.has_key?(schema, "enum") or value in schema["enum"]) and
        type?(value, schema["type"])

    if valid, do: constraints(value, schema, path), else: {:error, path}
  end

  defp type?(_, nil), do: true
  defp type?(v, "object"), do: is_map(v) and not is_struct(v)
  defp type?(v, "array"), do: is_list(v)
  defp type?(v, "string"), do: is_binary(v)
  defp type?(v, "boolean"), do: is_boolean(v)
  defp type?(v, "null"), do: is_nil(v)
  defp type?(v, "integer"), do: is_integer(v)

  defp constraints(value, %{"type" => "object", "additionalProperties" => item} = s, path)
       when is_map(item) do
    if map_size(value) >= s["minProperties"] and map_size(value) <= s["maxProperties"] do
      Enum.reduce_while(value, :ok, fn {k, v}, _ ->
        case check(v, item, path <> "." <> k) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    else
      {:error, path}
    end
  end

  defp constraints(value, %{"type" => "object"} = s, path) do
    props = s["properties"]

    if Enum.all?(s["required"], &Map.has_key?(value, &1)) and
         Enum.all?(Map.keys(value), &Map.has_key?(props, &1)) do
      Enum.reduce_while(value, :ok, fn {k, v}, _ ->
        case check(v, props[k], path <> "." <> k) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    else
      {:error, path}
    end
  end

  defp constraints(value, %{"type" => "array"} = s, path) do
    if length(value) >= s["minItems"] and length(value) <= s["maxItems"] and
         (s["uniqueItems"] != true or Enum.uniq(value) == value) do
      value
      |> Enum.with_index()
      |> Enum.reduce_while(:ok, fn {v, i}, _ ->
        case check(v, s["items"], path <> "[#{i}]") do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    else
      {:error, path}
    end
  end

  defp constraints(value, %{"type" => "string"} = s, path) do
    if String.length(value) >= Map.get(s, "minLength", 0) and
         String.length(value) <= Map.get(s, "maxLength", 1_048_576) and
         (is_nil(s["pattern"]) or Regex.match?(Regex.compile!(s["pattern"]), value)),
       do: :ok,
       else: {:error, path}
  end

  defp constraints(value, %{"type" => "integer"} = s, path) do
    if value >= s["minimum"] and value <= s["maximum"], do: :ok, else: {:error, path}
  end

  defp constraints(_, _, _), do: :ok
end
