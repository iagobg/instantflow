defmodule Instantflow.LocalTime do
  @moduledoc "PT-BR instant formatting using PostgreSQL's IANA timezone database. Date-only values stay separate."
  @batch_size 250
  def date(timezone, instant \\ DateTime.utc_now()) do
    %{rows: [[date]]} =
      Instantflow.Repo.query!("SELECT timezone($2::text, $1::timestamptz)::date", [
        instant,
        timezone
      ])

    date
  end

  def format_many(values, timezone) do
    format_batch(
      values,
      timezone,
      fn value ->
        {:ok, instant, _} = DateTime.from_iso8601(value)
        instant
      end,
      " (#{timezone})"
    )
  end

  @doc "Format distinct DateTime values in bounded batches; an empty collection issues no SQL."
  def format_instants(values, timezone \\ "America/Sao_Paulo") do
    suffix = if timezone == "America/Sao_Paulo", do: " (São Paulo)", else: " (#{timezone})"
    format_batch(values, timezone, fn %DateTime{} = instant -> instant end, suffix)
  end

  def format(%DateTime{} = instant, timezone \\ "America/Sao_Paulo"),
    do: Map.fetch!(format_instants([instant], timezone), instant)

  defp format_batch(values, timezone, to_instant, suffix) do
    values
    |> Enum.uniq()
    |> Enum.chunk_every(@batch_size)
    |> Enum.reduce(%{}, fn batch, formatted ->
      %{rows: rows} =
        Instantflow.Repo.query!(
          "SELECT to_char(timezone($2::text, value), 'DD/MM/YYYY HH24:MI') FROM unnest($1::timestamptz[]) WITH ORDINALITY AS dates(value, position) ORDER BY position",
          [Enum.map(batch, to_instant), timezone]
        )

      Map.merge(
        formatted,
        Map.new(Enum.zip(batch, rows), fn {value, [text]} -> {value, text <> suffix} end)
      )
    end)
  end
end
