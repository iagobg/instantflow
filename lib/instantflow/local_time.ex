defmodule Instantflow.LocalTime do
  @moduledoc "PT-BR instant formatting using PostgreSQL's IANA timezone database. Date-only values stay separate."
  def format_many([], _timezone), do: %{}

  def format_many(values, timezone) do
    instants =
      Enum.map(values, fn value ->
        {:ok, instant, _} = DateTime.from_iso8601(value)
        instant
      end)

    %{rows: rows} =
      Instantflow.Repo.query!(
        "SELECT to_char(timezone($2::text, value), 'DD/MM/YYYY HH24:MI') FROM unnest($1::timestamptz[]) WITH ORDINALITY AS dates(value, position) ORDER BY position",
        [instants, timezone]
      )

    Enum.zip(values, Enum.map(rows, fn [text] -> text <> " (#{timezone})" end)) |> Map.new()
  end

  def format(%DateTime{} = instant, timezone \\ "America/Sao_Paulo") do
    %{rows: [[formatted]]} =
      Instantflow.Repo.query!(
        "SELECT to_char(timezone($2::text, $1::timestamptz), 'DD/MM/YYYY HH24:MI')",
        [instant, timezone]
      )

    formatted <> if(timezone == "America/Sao_Paulo", do: " (São Paulo)", else: " (#{timezone})")
  end
end
