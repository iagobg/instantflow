defmodule Instantflow.WorkflowCatalog.Interchange do
  @moduledoc "Bounded JSON with duplicate-key rejection and deterministic object ordering."
  @limit 1_048_576

  def decode(json) when is_binary(json) and byte_size(json) <= @limit do
    with :ok <- scan_depth(json),
         {:ok, value} <- Jason.decode(json, objects: :ordered_objects) do
      {:ok, normalize(value, 0)}
    else
      _ -> {:error, :invalid_json}
    end
  catch
    :invalid_json -> {:error, :invalid_json}
  end

  def decode(_), do: {:error, :invalid_json}

  # Check depth before the recursive decoder allocates a deeply nested tree.
  defp scan_depth(json), do: scan_depth(json, 0, false, false)
  defp scan_depth(<<>>, 0, false, _), do: :ok
  defp scan_depth(<<>>, _, _, _), do: {:error, :invalid_json}
  defp scan_depth(<<_, rest::binary>>, n, true, true), do: scan_depth(rest, n, true, false)
  defp scan_depth(<<92, rest::binary>>, n, true, false), do: scan_depth(rest, n, true, true)

  defp scan_depth(<<34, rest::binary>>, n, quoted, false),
    do: scan_depth(rest, n, not quoted, false)

  defp scan_depth(<<c, rest::binary>>, n, false, false) when c in [123, 91] and n < 20,
    do: scan_depth(rest, n + 1, false, false)

  defp scan_depth(<<c, _::binary>>, 20, false, false) when c in [123, 91],
    do: {:error, :invalid_json}

  defp scan_depth(<<c, rest::binary>>, n, false, false) when c in [125, 93] and n > 0,
    do: scan_depth(rest, n - 1, false, false)

  defp scan_depth(<<_, rest::binary>>, n, quoted, escaped),
    do: scan_depth(rest, n, quoted, escaped)

  defp normalize(_, depth) when depth > 20, do: throw(:invalid_json)

  defp normalize(%Jason.OrderedObject{values: pairs}, depth) do
    keys = Enum.map(pairs, &elem(&1, 0))
    if Enum.uniq(keys) != keys, do: throw(:invalid_json)
    Map.new(pairs, fn {key, value} -> {key, normalize(value, depth + 1)} end)
  end

  defp normalize(list, depth) when is_list(list), do: Enum.map(list, &normalize(&1, depth + 1))
  defp normalize(value, _), do: value

  def encode(value), do: value |> ordered() |> Jason.encode!()
  def digest(value), do: :crypto.hash(:sha256, encode(value)) |> Base.encode16(case: :lower)

  defp ordered(map) when is_map(map),
    do:
      map
      |> Enum.sort()
      |> Enum.map(fn {k, v} -> {k, ordered(v)} end)
      |> Jason.OrderedObject.new()

  defp ordered(list) when is_list(list), do: Enum.map(list, &ordered/1)
  defp ordered(value), do: value
end
