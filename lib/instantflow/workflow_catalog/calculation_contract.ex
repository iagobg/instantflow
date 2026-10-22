defmodule Instantflow.WorkflowCatalog.CalculationContract do
  @moduledoc "Bounded integer-only schemas and reference-only calculation mappings."
  alias Instantflow.WorkflowCatalog.{Definition, Interchange}
  def key?(v), do: is_binary(v) and Regex.match?(~r/^[a-z][a-z0-9_]{0,63}$/, v)
  def digest?(v), do: is_binary(v) and Regex.match?(~r/^[a-f0-9]{64}$/, v)

  def schema?(s) when is_map(s) and map_size(s) in 1..16 do
    Enum.all?(s, fn {key, spec} ->
      key?(key) and is_map(spec) and Enum.sort(Map.keys(spec)) == ~w(max min type) and
        spec["type"] == "integer" and is_integer(spec["min"]) and is_integer(spec["max"]) and
        spec["min"] >= -1_000_000_000 and spec["max"] <= 1_000_000_000 and
        spec["min"] <= spec["max"]
    end)
  end

  def schema?(_), do: false

  def values?(s, values) when is_map(values) do
    schema?(s) and Enum.sort(Map.keys(s)) == Enum.sort(Map.keys(values)) and
      Enum.all?(values, fn {key, v} ->
        is_integer(v) and v >= s[key]["min"] and v <= s[key]["max"]
      end) and
      byte_size(Interchange.encode(values)) <= 16_384
  end

  def values?(_, _), do: false
  def spec?(nil, _), do: true

  def spec?(s, d) when is_map(s) do
    Enum.sort(Map.keys(s)) == ~w(digest inputs outputs script) and key?(s["script"]) and
      digest?(s["digest"]) and mapping?(s["inputs"], d) and mapping?(s["outputs"], d) and
      MapSet.disjoint?(MapSet.new(Map.values(s["inputs"])), MapSet.new(Map.values(s["outputs"]))) and
      confidential?(s, d) and financial_outputs?(s, d)
  end

  def spec?(_, _), do: false

  defp mapping?(m, d) when is_map(m) and map_size(m) in 1..16 do
    fields = Definition.fields(d)

    Enum.all?(m, fn {k, ref} -> key?(k) and get_in(fields, [ref, "type"]) in ~w(integer money) end) and
      Enum.uniq(Map.values(m)) == Map.values(m)
  end

  defp mapping?(_, _), do: false

  defp financial_outputs?(s, d) do
    protected =
      for t <- d["transitions"],
          t["finance"],
          field <- ~w(amount_field quantity_field received_field),
          ref = t["finance"][field],
          not is_nil(ref),
          do: ref

    Enum.all?(Map.values(s["outputs"]), &(&1 not in protected))
  end

  defp confidential?(s, d) do
    Enum.all?(sections(d, s["outputs"]), fn out ->
      Enum.all?(out["access"], &(&1["edit_stages"] == [])) and
        Enum.all?(sections(d, s["inputs"]), fn input ->
          (out["classification"] == "restricted" or input["classification"] == "internal") and
            MapSet.subset?(readers(out), readers(input))
        end)
    end)
  end

  def sections(d, m) do
    keys = m |> Map.values() |> Enum.map(&(String.split(&1, ".") |> hd()))
    Enum.filter(d["sections"], &(&1["key"] in keys))
  end

  defp readers(s),
    do:
      s["access"]
      |> Enum.filter(& &1["read"])
      |> Enum.map(&Map.drop(&1, ["read", "edit_stages"]))
      |> MapSet.new()

  def calculations?(d), do: Enum.any?(d["transitions"], & &1["calculation"])

  def computed?(d, key) when is_binary(key),
    do:
      Enum.any?(d["transitions"], fn t ->
        t["calculation"] &&
          Enum.any?(Map.values(t["calculation"]["outputs"]), &String.starts_with?(&1, key <> "."))
      end)

  def computed?(_, _), do: false
end
