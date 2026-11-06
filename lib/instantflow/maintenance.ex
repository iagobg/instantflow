defmodule Instantflow.Maintenance do
  @moduledoc "Bounded physical retention, independent of delivery polling and logical expiration."
  alias Instantflow.{Calculations, PrivateDocuments, Repo}
  require Logger

  def sweep(cursor \\ 0) when is_integer(cursor) and cursor >= 0 do
    started = System.monotonic_time()
    limit = Application.get_env(:instantflow, :maintenance_organizations_per_pass, 50)
    batch = Application.get_env(:instantflow, :maintenance_batch_size, 100)

    %{rows: rows} =
      Repo.query!("SELECT id FROM public.maintenance_organizations($1, $2)", [cursor, limit])

    counts =
      Enum.reduce(rows, %{documents: 0, calculations: 0, failures: 0}, fn [id], counts ->
        counts
        |> clean(:documents, fn -> PrivateDocuments.purge_expired(id, batch) end)
        |> clean(:calculations, fn -> Calculations.purge_expired(id, batch) end)
      end)

    :telemetry.execute(
      [:instantflow, :maintenance, :pass],
      Map.merge(counts, %{
        organizations: length(rows),
        duration: System.monotonic_time() - started
      }),
      %{}
    )

    Map.put(counts, :cursor, if(rows == [], do: 0, else: rows |> List.last() |> hd()))
  end

  defp clean(counts, category, fun) do
    result =
      try do
        fun.()
      rescue
        _ -> {:error, :cleanup_failed}
      end

    case result do
      {:ok, {count, _}} ->
        Map.update!(counts, category, &(&1 + count))

      {:error, _} ->
        Logger.warning("retention_batch_failed")
        Map.update!(counts, :failures, &(&1 + 1))
    end
  end
end
