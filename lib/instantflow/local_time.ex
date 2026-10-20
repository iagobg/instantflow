defmodule Instantflow.LocalTime do
  @moduledoc "PT-BR instant formatting using PostgreSQL's IANA timezone database. Date-only values stay separate."
  def format(%DateTime{} = instant) do
    %{rows: [[formatted]]} =
      Instantflow.Repo.query!(
        "SELECT to_char(timezone('America/Sao_Paulo', $1::timestamptz), 'DD/MM/YYYY HH24:MI')",
        [instant]
      )

    formatted <> " (São Paulo)"
  end
end
