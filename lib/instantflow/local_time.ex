defmodule Instantflow.LocalTime do
  @moduledoc "PT-BR instant formatting using PostgreSQL's IANA timezone database. Date-only values stay separate."
  def format(%DateTime{} = instant, timezone \\ "America/Sao_Paulo") do
    %{rows: [[formatted]]} =
      Instantflow.Repo.query!(
        "SELECT to_char(timezone($2::text, $1::timestamptz), 'DD/MM/YYYY HH24:MI')",
        [instant, timezone]
      )

    formatted <> if(timezone == "America/Sao_Paulo", do: " (São Paulo)", else: " (#{timezone})")
  end
end
