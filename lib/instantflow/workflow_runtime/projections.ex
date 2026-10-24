defmodule Instantflow.WorkflowRuntime.Projections do
  @moduledoc """
  Shared bounded authorized record selection and configured view projection.

  SQL applies pinned policies before counts, filters, ordering and LIMIT/OFFSET.
  Counts are pre-user-filter within the authorized workflow/view; `filtered`
  is post stage/query filter. Search covers only ID and pinned process name.
  Ordering is descending ticket ID, including across versions. Page size is 25.
  Only readable section rows for the selected page are fetched, in one batch.
  Catalog definitions are compiled once per referenced version, never once per ticket.
  Section and assignment projection predicates use only selected page versions.
  All operations hold the shared authorization gate, so revocation fences the
  whole projection. No configured view grants underlying record authority.
  """
  import Ecto.Query
  alias Instantflow.{Repo, Tenant}
  alias Instantflow.WorkflowCatalog.Version
  alias Instantflow.WorkflowRuntime.{ConfiguredQueries, PolicyQuery, Section, Ticket}

  @page_size 25

  @doc "Internal query for capability aggregates; caller must hold the tenant authorization gate."
  def authorized_query(scope, workflow_id) do
    predicate =
      versions(%{"workflow_id" => workflow_id}, :policy)
      |> PolicyQuery.groups()
      |> Enum.reduce(dynamic(false), fn [version | _] = equivalent, acc ->
        rule = PolicyQuery.discover(scope, version)
        ids = Enum.map(equivalent, & &1.id)
        dynamic([ticket: t], ^acc or (t.workflow_version_id in ^ids and ^rule))
      end)

    from t in Ticket,
      as: :ticket,
      where: t.organization_id == ^scope.organization_id,
      where: ^predicate
  end

  def participant_search(actor, workflow_id, page_key, filters \\ %{}) do
    Tenant.read(
      actor,
      fn scope ->
        result =
          fetch_page(
            scope,
            Map.put(filters, "workflow_id", positive_integer(workflow_id, 0)),
            {:participant, page_key}
          )

        rows =
          Enum.map(result.tickets, fn ticket ->
            version = result.versions[ticket.workflow_version_id]
            page = Instantflow.WorkflowCatalog.ParticipantPages.find(version.definition, page_key)

            %{
              id: ticket.id,
              label: page["label"],
              status: if(page["participant"]["status"], do: stage_label(version, ticket.stage))
            }
          end)

        %{rows: rows, total: result.filtered, page: result.page, pages: result.pages}
      end,
      %{rows: [], total: 0, page: 1, pages: 1}
    )
  end

  def participant_options(actor), do: participant_discovery(actor).rows

  def participant_discovery(actor, filters \\ %{}) do
    Tenant.read(
      actor,
      fn scope ->
        versions = versions(filters, :policy)

        predicate =
          Enum.reduce(PolicyQuery.groups(versions), dynamic(false), fn [version | _] = equivalent,
                                                                       acc ->
            ids = Enum.map(equivalent, & &1.id)

            Enum.reduce(
              Instantflow.WorkflowCatalog.ParticipantPages.pages(version.definition),
              acc,
              fn page, acc ->
                rule = participant_policy(scope, version, page)
                key = page["key"]

                dynamic(
                  [ticket: t],
                  ^acc or
                    (t.workflow_version_id in ^ids and
                       fragment("?->>'key'", parent_as(:page).value) == ^key and ^rule)
                )
              end
            )
          end)

        admitted =
          from t in Ticket,
            as: :ticket,
            where: t.organization_id == ^scope.organization_id,
            where: t.workflow_version_id == parent_as(:discovery_version).id,
            where: ^predicate,
            select: 1

        ids = Enum.map(versions, & &1.id)

        query =
          from v in Version,
            as: :discovery_version,
            join:
              p in fragment(
                "jsonb_array_elements(?->'interface'->'pages') WITH ORDINALITY",
                v.definition
              ),
            as: :page,
            on: true,
            where: v.id in ^ids,
            where: exists(subquery(admitted)),
            distinct: [v.workflow_id, fragment("?->>'key'", p.value)],
            order_by: [v.workflow_id, fragment("?->>'key'", p.value), desc: v.number, desc: v.id],
            select: %{
              workflow_id: v.workflow_id,
              key: fragment("?->>'key'", p.value),
              label: fragment("?->>'label'", p.value),
              process_label: fragment("?->>'name'", v.definition),
              position: fragment("?::int", p.ordinality),
              version_number: v.number
            }

        query = option_filter(query, filters, :participant)
        result = option_page(query, filters)
        %{result | rows: Enum.map(result.rows, &Map.put(&1, :id, "#{&1.workflow_id}:#{&1.key}"))}
      end,
      empty_options()
    )
  end

  def participant_policy(scope, version, page) do
    contract = Instantflow.WorkflowRuntime.ParticipantPolicy

    if page && contract.visible?(scope, version, page) do
      audience =
        Enum.reduce(page["participant"]["audience"], dynamic(false), fn spec, acc ->
          actor = PolicyQuery.actor(scope, version, spec)
          dynamic(^acc or ^actor)
        end)

      discover = PolicyQuery.discover(scope, version)
      dynamic(^discover and ^audience)
    else
      dynamic(false)
    end
  end

  def search(actor, filters \\ %{}) do
    Tenant.read(actor, &(fetch_page(&1, filters, nil) |> Map.delete(:versions)), empty())
  end

  def view(actor, workflow_id, key, filters \\ %{}) do
    Tenant.read(
      actor,
      fn scope ->
        result = fetch_page(scope, Map.put(filters, "workflow_id", workflow_id), key)
        project(scope, result, key)
      end,
      empty_view()
    )
  end

  def options(actor, filters \\ %{}), do: view_discovery(actor, filters).rows

  def view_discovery(actor, filters \\ %{}) do
    Tenant.read(
      actor,
      fn scope ->
        versions = versions(filters, :policy)

        predicate =
          Enum.reduce(PolicyQuery.groups(versions), dynamic(false), fn [version | _] = equivalent,
                                                                       acc ->
            ids = Enum.map(equivalent, & &1.id)

            Enum.reduce(version.definition["views"], acc, fn view, acc ->
              rule = view_policy(scope, version, view["key"])
              key = view["key"]

              dynamic(
                [ticket: t],
                ^acc or
                  (t.workflow_version_id in ^ids and
                     fragment("?->>'key'", parent_as(:declared_view).value) == ^key and
                     ^rule)
              )
            end)
          end)

        admitted =
          from t in Ticket,
            as: :ticket,
            where: t.organization_id == ^scope.organization_id,
            where: t.workflow_version_id == parent_as(:discovery_version).id,
            where: ^predicate,
            select: 1

        ids = Enum.map(versions, & &1.id)

        query =
          from version in Version,
            as: :discovery_version,
            join:
              view in fragment(
                "jsonb_array_elements(?->'views') WITH ORDINALITY",
                version.definition
              ),
            as: :declared_view,
            on: true,
            where: version.id in ^ids,
            where: exists(subquery(admitted)),
            distinct: [version.workflow_id, fragment("?->>'key'", view.value)],
            order_by: [
              version.workflow_id,
              fragment("?->>'key'", view.value),
              desc: version.number,
              desc: version.id
            ],
            select: %{
              workflow_id: version.workflow_id,
              version_id: version.id,
              key: fragment("?->>'key'", view.value),
              type: fragment("?->>'type'", view.value),
              urgency?: fragment("?->'urgency' IS NOT NULL", view.value),
              view_label: fragment("?->>'label'", view.value),
              process_label: fragment("?->>'name'", version.definition),
              position: fragment("?::int", view.ordinality),
              version_number: version.number
            }

        query =
          if filters["type"] == "board" do
            where(query, [declared_view: view], fragment("?->>'type'", view.value) == "board")
          else
            query
          end

        query = option_filter(query, filters, :view)
        result = option_page(query, filters)

        %{
          result
          | rows:
              Enum.map(result.rows, fn row ->
                row
                |> Map.put(:id, "#{row.workflow_id}:#{row.key}")
                |> Map.put(:label, "#{row.process_label} · #{row.view_label}")
              end)
        }
      end,
      empty_options()
    )
  end

  @doc "Resolve a historical board workspace only through authorized record/view discovery."
  def board_workspace(actor, workflow_id) when is_integer(workflow_id) and workflow_id > 0 do
    Tenant.read(actor, fn scope ->
      case view_discovery(scope, %{"workflow_id" => workflow_id, "type" => "board"}).rows do
        [option | _] -> Repo.get(Version, option.version_id)
        [] -> nil
      end
    end)
  end

  def board_workspace(_, _), do: nil

  @doc "Configured empty boards of an authorized current workspace, before its first case."
  def empty_board_discovery(actor, workflow_id, filters) do
    Tenant.read(
      actor,
      fn scope ->
        version = Instantflow.WorkflowCatalog.Workspaces.get(scope, workflow_id)

        views =
          if version do
            version.definition["views"]
            |> Enum.filter(&(&1["type"] == "board" and visible_view?(scope, version, &1)))
            |> Enum.map(&%{key: &1["key"], type: "board", view_label: &1["label"]})
          else
            []
          end

        pages = max(1, ceil(length(views) / @page_size))
        page = min(positive_integer(filters["page"], 1), pages)

        %{
          rows: Enum.slice(views, (page - 1) * @page_size, @page_size),
          total: length(views),
          page: page,
          pages: pages
        }
      end,
      empty_options()
    )
  end

  defp empty_options, do: %{rows: [], total: 0, page: 1, pages: 1}

  defp option_page(query, filters) do
    total = Repo.aggregate(query, :count)
    pages = max(1, ceil(total / @page_size))
    page = min(positive_integer(filters["page"], 1), pages)

    rows =
      Repo.all(
        from option in subquery(query),
          order_by: [
            asc: option.workflow_id,
            desc: option.version_number,
            asc: option.position,
            asc: option.key
          ],
          limit: @page_size,
          offset: ^((page - 1) * @page_size)
      )

    %{rows: rows, total: total, page: page, pages: pages}
  end

  defp option_filter(query, %{"query" => term}, kind) when is_binary(term) do
    term = "%" <> String.slice(String.trim(term), 0, 100) <> "%"

    case kind do
      :participant ->
        from [page: p] in query, where: ilike(fragment("?->>'label'", p.value), ^term)

      :view ->
        from [declared_view: v] in query, where: ilike(fragment("?->>'label'", v.value), ^term)
    end
  end

  defp option_filter(query, _, _), do: query

  @doc false
  def view_query(scope, versions, view_key) do
    # Group only identical declarations/bindings within this fresh scoped read.
    # Stage descriptors affect pinned display/count labels, not view admission.
    # Keep every actual version for rendering; no permission result is cached.
    predicate =
      versions
      |> PolicyQuery.groups()
      |> Enum.reduce(dynamic(false), fn [version | _] = equivalent, acc ->
        rule = view_policy(scope, version, view_key)
        ids = Enum.map(equivalent, & &1.id)
        dynamic([ticket: t], ^acc or (t.workflow_version_id in ^ids and ^rule))
      end)

    from t in Ticket,
      as: :ticket,
      where: t.organization_id == ^scope.organization_id,
      where: ^predicate
  end

  @doc false
  def filter_query(base, scope, versions, view_key, filters) do
    stage = text(filters["stage"])
    query = text(filters["query"]) |> String.downcase()

    names =
      versions
      |> Enum.filter(&String.contains?(String.downcase(&1.definition["name"]), query))
      |> Enum.map(& &1.id)

    filtered =
      from t in base,
        where: ^(stage == "") or t.stage == ^stage,
        where:
          ^(query == "") or t.workflow_version_id in ^names or
            fragment("strpos(?::text, ?) > 0", t.id, ^query)

    ConfiguredQueries.filter(filtered, scope, versions, view_key, filters)
  end

  defp fetch_page(scope, filters, view_key) do
    versions = versions(filters, if(is_binary(view_key), do: :full, else: :policy))
    by_id = Map.new(versions, &{&1.id, &1})

    base = view_query(scope, versions, view_key)

    groups =
      Repo.all(
        from t in base,
          group_by: [t.workflow_version_id, t.stage],
          select: {t.workflow_version_id, t.stage, count(t.id)}
      )

    counts =
      Enum.reduce(groups, %{}, fn {_, stage, count}, acc ->
        Map.update(acc, stage, count, &(&1 + count))
      end)

    labels =
      Enum.group_by(groups, fn {_, stage, _} -> stage end)
      |> Map.new(fn {stage, groups} ->
        labels =
          Enum.map(groups, fn {version_id, _, _} ->
            stage_label(Map.fetch!(by_id, version_id), stage)
          end)

        {stage, labels |> Enum.uniq() |> Enum.sort() |> Enum.join(" / ")}
      end)

    filtered = filter_query(base, scope, versions, view_key, filters)
    metadata = ConfiguredQueries.metadata(base, scope, versions, view_key)
    count = Repo.aggregate(filtered, :count)
    pages = max(1, ceil(count / @page_size))
    page = min(positive_integer(filters["page"], 1), pages)

    ordered =
      ConfiguredQueries.order(filtered, scope, versions, view_key, Enum.map(groups, &elem(&1, 0)))

    tickets =
      Repo.all(
        from t in ordered,
          limit: @page_size,
          offset: ^((page - 1) * @page_size)
      )

    tickets =
      Enum.map(tickets, fn ticket ->
        version = Map.fetch!(by_id, ticket.workflow_version_id)

        %{
          ticket
          | workflow_version: %{
              version
              | bindings: %{},
                definition: Map.take(version.definition, ~w(name stages))
            }
        }
      end)

    %{
      tickets: tickets,
      total: Enum.sum(Map.values(counts)),
      filtered: count,
      counts: counts,
      stage_labels: labels,
      page: page,
      pages: pages,
      versions: by_id,
      query_metadata: metadata
    }
  end

  defp view_policy(scope, version, {:participant, key}),
    do:
      participant_policy(
        scope,
        version,
        Instantflow.WorkflowCatalog.ParticipantPages.find(version.definition, key)
      )

  defp view_policy(scope, version, nil) do
    if generic_surface?(scope, version),
      do: PolicyQuery.discover(scope, version),
      else: dynamic(false)
  end

  defp view_policy(scope, version, key) do
    view = Enum.find(version.definition["views"], &(&1["key"] == key))

    if visible_view?(scope, version, view) do
      # A section permission applies to every selected field in that section.
      # Compile it once, keeping builtin-column visibility semantics unchanged.
      columns =
        if Enum.any?(view["columns"], &(&1 in ~w(stage assigned_department))) do
          dynamic(true)
        else
          view["columns"]
          |> Enum.map(&(String.split(&1, ".") |> hd()))
          |> Enum.uniq()
          |> Enum.reduce(dynamic(false), fn section_key, acc ->
            section = Enum.find(version.definition["sections"], &(&1["key"] == section_key))
            rule = PolicyQuery.section(scope, version, section)
            dynamic(^acc or ^rule)
          end)
        end

      discover = PolicyQuery.discover(scope, version)
      dynamic(^discover and ^columns)
    else
      dynamic(false)
    end
  end

  @doc false
  def visible_view?(scope, version, view) do
    not is_nil(view) and generic_surface?(scope, version) and
      (is_nil(view["visibility_roles"]) or
         Enum.any?(
           view["visibility_roles"],
           &Instantflow.Access.role?(scope, version.bindings["roles"][&1] || [])
         ))
  end

  defp generic_surface?(scope, version) do
    Instantflow.WorkflowCatalog.ParticipantPages.pages(version.definition) == [] or
      Instantflow.WorkflowRuntime.ParticipantPolicy.staff_workspace?(scope, version)
  end

  @doc false
  def versions(filters, mode) do
    # Only record-bearing pins participate in record discovery/count/projection.
    # Latest publications for creation remain owned by the workspace catalog.
    referenced =
      from t in Ticket,
        where:
          t.workflow_version_id == parent_as(:version).id and
            t.organization_id == parent_as(:version).organization_id

    query =
      from v in Version,
        as: :version,
        where: exists(subquery(referenced)),
        order_by: [desc: v.number, desc: v.id]

    query =
      if filters["workflow_id"],
        do: where(query, [v], v.workflow_id == ^positive_integer(filters["workflow_id"], 0)),
        else: query

    # Discovery and participant status pages compile section policies, not field
    # schemas. Do not transfer field definitions that those reads cannot use.
    body =
      if mode == :policy do
        dynamic(
          [v],
          fragment(
            "jsonb_set(? - ARRAY['stages','transitions','description','role_requirements','bindings','format_version','template_key','template_version','locale']::text[], '{sections}', (SELECT COALESCE(jsonb_agg(s.value - 'fields'), '[]'::jsonb) FROM jsonb_array_elements(?->'sections') AS s(value)))",
            v.definition,
            v.definition
          )
        )
      else
        dynamic([v], fragment("? - 'stages'", v.definition))
      end

    selection = %{
      organization_id: dynamic([v], v.organization_id),
      workflow_id: dynamic([v], v.workflow_id),
      bindings: dynamic([v], v.bindings),
      body: body,
      pins:
        dynamic(
          [v],
          fragment(
            "jsonb_agg(jsonb_build_object('id', ?, 'number', ?, 'stages', ?->'stages'))",
            v.id,
            v.number,
            v.definition
          )
        )
    }

    # Fetch repeated immutable bodies once, with each actual pin's stages.
    query
    |> exclude(:order_by)
    |> group_by(^[:organization_id, :workflow_id, :bindings, body])
    |> select(^selection)
    |> Repo.all()
    |> Enum.flat_map(fn %{
                          organization_id: org,
                          workflow_id: workflow,
                          bindings: bindings,
                          body: body,
                          pins: pins
                        } ->
      Enum.map(pins, fn pin ->
        %Version{
          id: pin["id"],
          organization_id: org,
          workflow_id: workflow,
          number: pin["number"],
          bindings: bindings,
          definition: Map.put(body, "stages", pin["stages"])
        }
      end)
    end)
    |> Enum.sort_by(&{&1.number, &1.id}, :desc)
  end

  @doc false
  def project(scope, result, key) do
    page_versions =
      Map.take(result.versions, Enum.map(result.tickets, & &1.workflow_version_id))

    # This OR predicate permits only readable sections of already authorized page
    # records. Hidden content never leaves the database, even for projection.
    predicate =
      Enum.reduce(page_versions, dynamic(false), fn {id, version}, acc ->
        ids = result.tickets |> Enum.filter(&(&1.workflow_version_id == id)) |> Enum.map(& &1.id)

        Enum.reduce(version.definition["sections"], acc, fn section, acc ->
          rule = PolicyQuery.section(scope, version, section)
          key = section["key"]
          dynamic([s, ticket: t], ^acc or (s.ticket_id in ^ids and s.key == ^key and ^rule))
        end)
      end)

    sections =
      Repo.all(
        from s in Section,
          join: t in Ticket,
          as: :ticket,
          on: t.id == s.ticket_id,
          where: ^predicate,
          select: {s.ticket_id, s.key, s.values}
      )
      |> Map.new(fn {id, key, values} -> {{id, key}, values} end)

    department_ids = Enum.map(result.tickets, & &1.assigned_department_id) |> Enum.uniq()

    departments =
      Repo.all(
        from d in Instantflow.Identity.Department,
          where: d.id in ^department_ids,
          select: {d.id, d.name}
      )
      |> Map.new()

    assignment_rule =
      Enum.reduce(page_versions, dynamic(false), fn {version_id, version}, acc ->
        view = ConfiguredQueries.view(version, key)
        section = view && view["assignment_section"]

        if section do
          permission = ConfiguredQueries.assignment_permission(scope, version, section)

          dynamic(
            [assignment: a, ticket: t],
            ^acc or
              (t.workflow_version_id == ^version_id and a.section_key == ^section and ^permission)
          )
        else
          acc
        end
      end)

    ids = Enum.map(result.tickets, & &1.id)

    assignments =
      Repo.all(
        from a in Instantflow.Collaboration.Assignment,
          as: :assignment,
          join: t in Ticket,
          as: :ticket,
          on: t.id == a.ticket_id,
          join: m in Instantflow.Identity.Membership,
          on: m.id == a.membership_id,
          join: u in Instantflow.Identity.User,
          on: u.id == m.user_id,
          where: a.ticket_id in ^ids,
          where: ^assignment_rule,
          select: {a.ticket_id, a.section_key, u.name}
      )
      |> Map.new(fn {id, section, name} -> {{id, section}, name} end)

    fields_by_version =
      Map.new(page_versions, fn {id, v} ->
        {id, Instantflow.WorkflowCatalog.Definition.fields(v.definition)}
      end)

    rows =
      Enum.map(result.tickets, fn ticket ->
        version = Map.fetch!(result.versions, ticket.workflow_version_id)
        view = Enum.find(version.definition["views"], &(&1["key"] == key))
        fields = Map.fetch!(fields_by_version, version.id)

        cells =
          Enum.flat_map(view["columns"], fn
            "stage" ->
              [%{key: "stage", label: "Etapa", value: stage_label(version, ticket.stage)}]

            "assigned_department" ->
              [
                %{
                  key: "assigned_department",
                  label: "Departamento atribuído",
                  value: departments[ticket.assigned_department_id]
                }
              ]

            ref ->
              [section_key, field_key] = String.split(ref, ".")
              values = Map.get(sections, {ticket.id, section_key})
              field = fields[ref]

              if values,
                do: [%{key: ref, label: field["label"], value: values[field_key]}],
                else: []
          end)

        %{
          id: ticket.id,
          title:
            Enum.find_value(cells, fn cell ->
              field = fields[cell.key]

              if field && field["type"] in ~w(short_text long_text) &&
                   is_binary(cell.value) && String.trim(cell.value) != "", do: cell.value
            end) || "Registro ##{ticket.id}",
          version_id: version.id,
          type: view["type"],
          label: view["label"],
          stage: ticket.stage,
          stage_label: stage_label(version, ticket.stage),
          assignment: assignments[{ticket.id, view["assignment_section"]}],
          urgency:
            projected_value(sections, ticket.id, view["urgency"] && view["urgency"]["field"]),
          date_kind:
            if(view["calendar_field"],
              do: fields[view["calendar_field"]]["type"]
            ),
          date:
            projected_value(sections, ticket.id, view["calendar_field"]) ||
              Enum.find_value(cells, fn cell ->
                field =
                  fields[cell.key]

                if field && field["type"] == "date", do: cell.value
              end),
          cells: cells
        }
      end)

    instants =
      rows
      |> Enum.filter(&(&1.date_kind == "datetime" and is_binary(&1.date)))
      |> Enum.map(& &1.date)
      |> Enum.uniq()

    formatted =
      if instants == [],
        do: %{},
        else:
          Instantflow.LocalTime.format_many(
            instants,
            Repo.one!(
              from o in Instantflow.Identity.Organization,
                where: o.id == ^scope.organization_id,
                select: o.timezone
            )
          )

    rows =
      Enum.map(rows, fn row ->
        if row.date_kind == "datetime" && row.date,
          do: %{row | date: formatted[row.date]},
          else: row
      end)

    %{
      rows: rows,
      total: result.filtered,
      page: result.page,
      pages: result.pages,
      filters: result.query_metadata.filters,
      urgent: result.query_metadata.urgent,
      assignment?: result.query_metadata.assignment?,
      columns:
        rows
        |> Enum.flat_map(& &1.cells)
        |> Enum.uniq_by(& &1.key)
        |> Enum.map(&Map.take(&1, [:key, :label])),
      stages:
        result.counts
        |> Enum.sort()
        |> Enum.map(fn {id, count} -> %{id: id, label: result.stage_labels[id], count: count} end)
    }
  end

  defp projected_value(_, _, nil), do: nil

  defp projected_value(sections, id, ref) do
    [section, field] = String.split(ref, ".")
    (sections[{id, section}] || %{})[field]
  end

  defp stage_label(version, key),
    do: Enum.find(version.definition["stages"], &(&1["key"] == key))["label"]

  defp text(value) when is_binary(value), do: String.slice(value, 0, 100)
  defp text(_), do: ""

  defp positive_integer(value, _) when is_integer(value) and value > 0,
    do: min(value, 9_223_372_036_854_775_807)

  defp positive_integer(value, default) when is_binary(value) and byte_size(value) <= 18 do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> default
    end
  end

  defp positive_integer(_, default), do: default

  defp empty,
    do: %{tickets: [], total: 0, filtered: 0, counts: %{}, stage_labels: %{}, page: 1, pages: 1}

  defp empty_view,
    do: %{
      rows: [],
      total: 0,
      columns: [],
      stages: [],
      page: 1,
      pages: 1,
      filters: [],
      urgent: 0,
      assignment?: false
    }
end
