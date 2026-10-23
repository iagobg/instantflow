defmodule Instantflow.WorkflowCatalog.Workspaces do
  @moduledoc "Tenant-authorized, paged discovery and targeted access for published process workspaces."
  import Ecto.Query
  alias Instantflow.{Access, Repo, Tenant}
  alias Instantflow.WorkflowCatalog.Version

  defdelegate block_label(block), to: Instantflow.WorkflowCatalog.Interface
  defdelegate blocks(), to: Instantflow.WorkflowCatalog.Interface
  defdelegate operational_blocks(), to: Instantflow.WorkflowCatalog.Interface
  defdelegate operational?(definition), to: Instantflow.WorkflowCatalog.Interface
  defdelegate labels(definition), to: Instantflow.WorkflowCatalog.Interface
  defdelegate pages(definition), to: Instantflow.WorkflowCatalog.Interface
  defdelegate close_transition(definition), to: Instantflow.WorkflowCatalog.Interface
  defdelegate configuration(definition), to: Instantflow.WorkflowCatalog.Interface
  defdelegate validate(definition), to: Instantflow.WorkflowCatalog.Interface

  def allowed?(scope, version, action) do
    roles =
      get_in(version.definition, ["interface", "access", action]) ||
        version.definition["creation"]["roles"]

    Enum.any?(roles, &Access.role?(scope, version.bindings["roles"][&1] || []))
  end

  @doc false
  def latest_query do
    from v in Version, distinct: v.workflow_id, order_by: [asc: v.workflow_id, desc: v.number]
  end

  @doc "Internal query; callers hold Tenant's gate with a fresh scope. Selection precedes paging."
  def authorized_query(scope, kind) do
    base = from v in subquery(latest_query()), as: :workspace
    creation = role_rule(scope, :creation)

    if kind == :creation do
      retired =
        from r in "retired_workflow_versions",
          where: r.version_id == parent_as(:workspace).id,
          select: 1

      from v in base, where: ^creation, where: not exists(subquery(retired))
    else
      history =
        from old in Version,
          where: old.workflow_id == parent_as(:workspace).workflow_id,
          where:
            fragment(
              "jsonb_exists(?, 'communications') OR jsonb_path_exists(?, '$.interface.pages[*].participant')",
              old.definition,
              old.definition
            ),
          select: 1

      staff = role_rule(scope, :staff)
      declared = role_rule(scope, :declared)

      predicate =
        dynamic(
          (exists(subquery(history)) and ^staff) or (not exists(subquery(history)) and ^declared)
        )

      from v in base, where: ^predicate
    end
  end

  def search(scope, filters \\ %{}) do
    Tenant.read(
      scope,
      fn fresh -> page(authorized_query(fresh, :workspace), filters) end,
      empty()
    )
  end

  def installed(scope), do: search(scope).rows

  def get(scope, id) when is_integer(id) do
    Tenant.read(scope, fn fresh ->
      Repo.one(from v in authorized_query(fresh, :workspace), where: v.workflow_id == ^id)
    end)
  end

  def get(_, _), do: nil

  def navigation(scope) do
    Tenant.read(
      scope,
      fn fresh ->
        Repo.all(
          from v in authorized_query(fresh, :workspace),
            order_by: v.workflow_id,
            limit: 25,
            select: %{id: v.workflow_id, label: fragment("?->>'name'", v.definition)}
        )
      end,
      []
    )
  end

  @doc false
  def page(query, filters) do
    query =
      if is_binary(filters["query"]) and String.trim(filters["query"]) != "" do
        term = "%" <> String.slice(String.trim(filters["query"]), 0, 100) <> "%"
        from v in query, where: ilike(fragment("?->>'name'", v.definition), ^term)
      else
        query
      end

    query =
      if is_integer(filters["workflow_id"]),
        do: from(v in query, where: v.workflow_id == ^filters["workflow_id"]),
        else: query

    total = Repo.aggregate(query, :count)
    pages = max(1, ceil(total / 25))
    number = min(page_number(filters["page"]), pages)

    rows =
      Repo.all(from v in query, order_by: v.workflow_id, limit: 25, offset: ^((number - 1) * 25))

    %{rows: rows, page: number, pages: pages, total: total}
  end

  @doc false
  def operational_candidates(scope) do
    sessions =
      from s in Instantflow.Operations.Session,
        where: s.workflow_id == parent_as(:workspace).workflow_id,
        select: 1

    products =
      from p in Instantflow.Operations.Product,
        where: p.workflow_id == parent_as(:workspace).workflow_id,
        select: 1

    resources =
      from r in Instantflow.Operations.Resource,
        where: r.workflow_id == parent_as(:workspace).workflow_id,
        select: 1

    query =
      from v in subquery(latest_query()),
        as: :workspace,
        where:
          fragment("jsonb_exists(?->'capabilities', 'operations')", v.definition) or
            exists(subquery(sessions)) or exists(subquery(products)) or
            exists(subquery(resources))

    query = if scope, do: where(query, ^role_rule(scope, :operate_view)), else: query
    Repo.all(from v in query, order_by: v.workflow_id, limit: 2)
  end

  defp role_rule(scope, kind) do
    roles = Access.profiles(scope) |> Enum.map(& &1.role) |> Enum.uniq()

    case kind do
      :creation ->
        dynamic(
          [workspace: v],
          fragment(
            "EXISTS (SELECT 1 FROM jsonb_each(?->'roles') r WHERE jsonb_exists_any(r.value, ?) AND jsonb_exists(?->'creation'->'roles', r.key))",
            v.bindings,
            ^roles,
            v.definition
          )
        )

      :staff ->
        dynamic(
          [workspace: v],
          fragment(
            "EXISTS (SELECT 1 FROM jsonb_each(?->'roles') r WHERE jsonb_exists_any(r.value, ?) AND (jsonb_exists(?->'creation'->'roles', r.key) OR jsonb_exists(?->'interface'->'access'->'view', r.key)))",
            v.bindings,
            ^roles,
            v.definition,
            v.definition
          )
        )

      :declared ->
        dynamic(
          [workspace: v],
          fragment(
            "EXISTS (SELECT 1 FROM jsonb_each(?->'roles') r WHERE jsonb_exists_any(r.value, ?) AND EXISTS (SELECT 1 FROM jsonb_array_elements(?->'role_requirements') spec WHERE spec->>'key' = r.key))",
            v.bindings,
            ^roles,
            v.definition
          )
        )

      :operate_view ->
        dynamic(
          [workspace: v],
          fragment(
            "EXISTS (SELECT 1 FROM jsonb_each(?->'roles') r WHERE jsonb_exists_any(r.value, ?) AND jsonb_exists(COALESCE(?->'interface'->'access'->'view', ?->'creation'->'roles'), r.key))",
            v.bindings,
            ^roles,
            v.definition,
            v.definition
          )
        )
    end
  end

  defp empty, do: %{rows: [], page: 1, pages: 1, total: 0}
  defp page_number(n) when is_integer(n) and n > 0, do: min(n, 1_000_000_000)

  defp page_number(n) when is_binary(n) and byte_size(n) <= 18 do
    case Integer.parse(n) do
      {n, ""} when n > 0 -> min(n, 1_000_000_000)
      _ -> 1
    end
  end

  defp page_number(_), do: 1
end
