defmodule Instantflow.Operations.ReadModel do
  @moduledoc "Operational SQL projections. Called inside Operations' current tenant/permission gate."
  import Ecto.Query
  alias Instantflow.Repo
  alias Instantflow.Operations.{Batch, DayClose, Line, Product, Resource, Session}

  @page_size 25
  @batch_page_size 10

  def products(workflow_id, params) do
    query = from p in Product, where: p.workflow_id == ^workflow_id
    query = search(query, params["products_query"], :product)
    page(query, params["products_page"], @page_size, asc: :category, asc: :name, asc: :id)
  end

  def resources(workflow_id, params) do
    query = from r in Resource, where: r.workflow_id == ^workflow_id
    query = search(query, params["resources_query"], :resource)
    page(query, params["resources_page"], @page_size, asc: :name, asc: :id)
  end

  def sessions(workflow_id, resources) do
    ids = Enum.map(resources, & &1.id)

    Repo.all(
      from s in Session,
        where: s.workflow_id == ^workflow_id and s.resource_id in ^ids and s.status == "open",
        order_by: s.id,
        limit: @page_size
    )
  end

  def batches(session_id, params) do
    {batches, pagination} =
      page(
        from(b in Batch, where: b.session_id == ^session_id),
        params["batches_page"],
        @batch_page_size,
        asc: :id
      )

    ids = Enum.map(batches, & &1.id)
    # Supported batch commands accept at most 100 captured lines per batch.
    lines = Repo.all(from l in Line, where: l.batch_id in ^ids, order_by: l.id)
    grouped = Enum.group_by(lines, & &1.batch_id)
    {Enum.map(batches, &Map.put(&1, :lines, Map.get(grouped, &1.id, []))), pagination}
  end

  def report(date, workflow_id, params \\ %{}, mode \\ :page) do
    stats =
      Repo.all(
        from s in Session,
          where: s.workflow_id == ^workflow_id and s.business_date == ^date,
          group_by: [s.status, s.payment_method],
          select: %{
            status: s.status,
            method: s.payment_method,
            count: count(s.id),
            total: fragment("SUM(?)::bigint", s.total)
          }
      )

    lines =
      from l in Line,
        join: b in Batch,
        on: b.id == l.batch_id,
        join: s in Session,
        on: s.id == b.session_id,
        where: s.workflow_id == ^workflow_id and s.business_date == ^date and b.kind == "order"

    amounts =
      Repo.all(
        from [l, b, s] in lines,
          group_by: [s.status, b.status],
          select: %{
            session_status: s.status,
            batch_status: b.status,
            amount: fragment("COALESCE(SUM(?::bigint * ?), 0)::bigint", l.unit_price, l.quantity)
          }
      )

    consumption_query =
      from [l, b, _s] in lines,
        where: b.status != "cancelled",
        group_by: l.product_id,
        select: %{
          product_id: l.product_id,
          name: fragment("(array_agg(? ORDER BY ? DESC))[1]", l.name, l.id),
          quantity: fragment("SUM(?)::bigint", l.quantity)
        }

    consumption_query = from(c in subquery(consumption_query))

    {consumption, pagination} =
      if mode == :snapshot do
        rows = Repo.all(from c in consumption_query, order_by: [c.name, c.product_id])
        {rows, %{total: length(rows), page: 1, pages: 1, page_size: nil}}
      else
        page(consumption_query, params["consumption_page"], @page_size,
          asc: :name,
          asc: :product_id
        )
      end

    closed =
      Repo.one(
        from d in DayClose,
          where: d.workflow_id == ^workflow_id and d.business_date == ^date,
          select: d,
          select_merge: %{summary: fragment("? - 'consumption'", d.summary)}
      )

    %{
      date: date,
      sales: stat_sum(stats, "settled", :total),
      settled_count: stat_sum(stats, "settled", :count),
      open_count: stat_sum(stats, "open", :count),
      open_total: amount_sum(amounts, "open"),
      archived_count: stat_sum(stats, "archived", :count),
      archived_total: amount_sum(amounts, "archived"),
      payments:
        Map.new(~w(cash card pix), fn method ->
          {method,
           stats
           |> Enum.filter(&(&1.status == "settled" and &1.method == method))
           |> Enum.map(& &1.total)
           |> Enum.sum()}
        end),
      cancellations:
        amounts
        |> Enum.filter(&(&1.batch_status == "cancelled"))
        |> Enum.map(& &1.amount)
        |> Enum.sum(),
      consumption: consumption,
      pagination: pagination,
      closed: closed
    }
  end

  def empty_page(size \\ @page_size), do: %{total: 0, page: 1, pages: 1, page_size: size}

  defp stat_sum(rows, status, key),
    do:
      rows |> Enum.filter(&(&1.status == status)) |> Enum.map(&Map.fetch!(&1, key)) |> Enum.sum()

  defp amount_sum(rows, status),
    do:
      rows
      |> Enum.filter(&(&1.session_status == status and &1.batch_status != "cancelled"))
      |> Enum.map(& &1.amount)
      |> Enum.sum()

  defp page(query, requested, size, order) do
    total = Repo.aggregate(query, :count)
    pages = max(1, ceil(total / size))
    page = min(page_number(requested), pages)

    {Repo.all(from row in query, order_by: ^order, limit: ^size, offset: ^((page - 1) * size)),
     %{total: total, page: page, pages: pages, page_size: size}}
  end

  defp page_number(n) when is_integer(n) and n > 0, do: min(n, 1_000_000_000)

  defp page_number(n) when is_binary(n) and byte_size(n) <= 18 do
    case Integer.parse(n) do
      {n, ""} when n > 0 -> min(n, 1_000_000_000)
      _ -> 1
    end
  end

  defp page_number(_), do: 1

  defp search(query, text, kind) when is_binary(text) do
    term =
      text
      |> String.slice(0, 100)
      |> String.normalize(:nfd)
      |> String.replace(~r/\p{Mn}/u, "")
      |> String.downcase()
      |> String.trim()

    if term == "", do: query, else: search_term(query, term, kind)
  end

  defp search(query, _, _), do: query

  defp search_term(query, term, :product),
    do:
      from(p in query,
        where:
          fragment(
            "strpos(translate(lower(? || ' ' || ?), 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'aaaaaeeeeiiiiooooouuuucaaaaaeeeeiiiiooooouuuuc'), ?) > 0",
            p.name,
            p.category,
            ^term
          )
      )

  defp search_term(query, term, :resource),
    do:
      from(r in query,
        where:
          fragment(
            "strpos(translate(lower(?), 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'aaaaaeeeeiiiiooooouuuucaaaaaeeeeiiiiooooouuuuc'), ?) > 0",
            r.name,
            ^term
          )
      )
end
