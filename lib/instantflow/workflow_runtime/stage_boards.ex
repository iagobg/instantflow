defmodule Instantflow.WorkflowRuntime.StageBoards do
  @moduledoc "Version-separated stage boards over the shared authorized record projection."
  import Ecto.Query
  alias Instantflow.{Repo, Tenant}
  alias Instantflow.WorkflowCatalog.{Retirement, Version}
  alias Instantflow.WorkflowRuntime.{BoardVersions, ConfiguredQueries, Projections}

  @card_limit 10
  @column_limit 10
  @version_limit 25

  def read(actor, workflow_id, key, filters)
      when is_integer(workflow_id) and workflow_id > 0 and is_binary(key) and is_map(filters) do
    Tenant.read(actor, fn scope -> read_scoped(scope, workflow_id, key, filters) end, empty())
  end

  def read(_, _, _, _), do: empty()

  defp read_scoped(scope, workflow_id, key, filters) do
    %{eligible: eligible, latest_id: latest_id} = BoardVersions.discover(scope, workflow_id, key)

    version_pages = max(1, ceil(length(eligible) / @version_limit))
    version_page = min(positive(filters["version_page"], 1), version_pages)
    selected_index = Enum.find_index(eligible, &(&1.id == positive(filters["version_id"], 0)))

    version_page =
      if selected_index, do: div(selected_index, @version_limit) + 1, else: version_page

    options = Enum.slice(eligible, (version_page - 1) * @version_limit, @version_limit)

    selected =
      if filters["version_id"] in [nil, ""],
        do: List.first(options),
        else: Enum.find(eligible, &(&1.id == positive(filters["version_id"], 0)))

    navigation = %{
      version_options: Enum.map(options, &%{id: &1.id, number: &1.number}),
      version_page: version_page,
      version_pages: version_pages,
      version_total: length(eligible)
    }

    if selected do
      version = Repo.get!(Version, selected.id)
      base = Projections.view_query(scope, [version], key)
      board(scope, key, filters, version, latest_id, base) |> Map.merge(navigation)
    else
      empty() |> Map.merge(navigation)
    end
  end

  defp board(scope, key, filters, version, latest_id, base) do
    base = where(base, [ticket: t], t.workflow_version_id == ^version.id)
    filtered = Projections.filter_query(base, scope, [version], key, filters)

    counts =
      Repo.all(from t in filtered, group_by: t.stage, select: {t.stage, count(t.id)}) |> Map.new()

    stages = version.definition["stages"]
    column_pages = max(1, ceil(length(stages) / @column_limit))
    column_page = min(positive(filters["columns_page"], 1), column_pages)
    stage_pages = if is_map(filters["column_pages"]), do: filters["column_pages"], else: %{}

    columns =
      stages
      |> Enum.slice((column_page - 1) * @column_limit, @column_limit)
      |> Enum.map(fn stage ->
        count = Map.get(counts, stage["key"], 0)
        pages = max(1, ceil(count / @card_limit))

        %{
          id: stage["key"],
          label: stage["label"],
          initial?: stage["initial"],
          terminal?: stage["terminal"],
          total: count,
          pages: pages,
          page: min(positive(stage_pages[stage["key"]], 1), pages)
        }
      end)

    tickets =
      Enum.flat_map(columns, fn column ->
        if column.total == 0 do
          []
        else
          filtered
          |> where([ticket: t], t.stage == ^column.id)
          |> ConfiguredQueries.order(scope, [version], key, [version.id])
          |> limit(@card_limit)
          |> offset(^((column.page - 1) * @card_limit))
          |> Repo.all()
        end
      end)

    metadata = ConfiguredQueries.metadata(base, scope, [version], key)

    projected =
      Projections.project(
        scope,
        %{
          tickets: tickets,
          versions: %{version.id => version},
          filtered: Enum.sum(Map.values(counts)),
          counts: counts,
          stage_labels: Map.new(stages, &{&1["key"], &1["label"]}),
          page: 1,
          pages: 1,
          query_metadata: metadata
        },
        key
      )

    columns =
      Enum.map(columns, fn column ->
        Map.put(column, :rows, Enum.filter(projected.rows, &(&1.stage == column.id)))
      end)

    Map.merge(projected, %{
      available?: true,
      version: %{
        id: version.id,
        number: version.number,
        current?: latest_id == version.id,
        archived?: Retirement.retired?(version.id)
      },
      columns: columns,
      stages: Enum.map(stages, &%{id: &1["key"], label: &1["label"]}),
      columns_page: column_page,
      columns_pages: column_pages,
      stage_total: length(stages),
      loaded: length(tickets),
      card_limit: @card_limit
    })
  end

  defp positive(value, default) when is_binary(value) and byte_size(value) <= 18 do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> min(number, 1_000_000_000)
      _ -> default
    end
  end

  defp positive(value, _) when is_integer(value) and value > 0, do: min(value, 1_000_000_000)
  defp positive(_, default), do: default

  def empty do
    %{
      available?: false,
      version: nil,
      version_options: [],
      version_page: 1,
      version_pages: 1,
      version_total: 0,
      columns: [],
      stages: [],
      rows: [],
      total: 0,
      loaded: 0,
      columns_page: 1,
      columns_pages: 1,
      stage_total: 0,
      card_limit: @card_limit,
      filters: [],
      urgent: 0,
      assignment?: false
    }
  end
end
