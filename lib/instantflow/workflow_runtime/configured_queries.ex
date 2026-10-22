defmodule Instantflow.WorkflowRuntime.ConfiguredQueries do
  @moduledoc "SQL filters and ordering over authorized pinned view fields; no ticket materialization."
  import Ecto.Query
  alias Instantflow.Repo
  alias Instantflow.WorkflowRuntime.PolicyQuery
  alias Instantflow.WorkflowCatalog.Definition

  def view(version, key), do: Enum.find(version.definition["views"], &(&1["key"] == key))

  def filter(query, scope, versions, key, params) when is_binary(key) do
    selections = if is_map(params["fields"]), do: Enum.take(params["fields"], 10), else: []

    Enum.reduce(selections, query, fn {ref, input}, query ->
      if input in [nil, ""] do
        query
      else
        rule =
          Enum.reduce(versions, dynamic(false), fn v, acc ->
            spec = view(v, key)

            if spec && ref in (spec["filters"] || []) && is_binary(input) &&
                 byte_size(input) <= 100 do
              value = field_value(scope, v, ref)
              typed = cast(Definition.fields(v.definition)[ref]["type"], input)
              match = dynamic(fragment("? = ?::jsonb", ^value, ^typed))
              dynamic([ticket: t], ^acc or (t.workflow_version_id == ^v.id and ^match))
            else
              acc
            end
          end)

        where(query, ^rule)
      end
    end)
    |> assignment_filter(scope, versions, key, params["assigned_to"])
  end

  def filter(query, _, _, _, _), do: query

  def order(query, scope, versions, key, authorized_ids) when is_binary(key) do
    relevant = Enum.filter(versions, &(&1.id in authorized_ids and view(&1, key)))
    first = List.first(relevant)
    sort = first && view(first, key)["sort"]

    if sort do
      value =
        Enum.reduce(relevant, dynamic(fragment("NULL::jsonb")), fn v, acc ->
          field = get_in(view(v, key), ["sort", "field"]) || "id"

          expr =
            case field do
              "id" -> dynamic([ticket: t], fragment("to_jsonb(?)", t.id))
              "stage" -> dynamic([ticket: t], fragment("to_jsonb(?)", t.stage))
              "urgency" -> urgency_rank(scope, v, key)
              ref -> field_value(scope, v, ref, true)
            end

          dynamic(
            [ticket: t],
            fragment(
              "CASE WHEN ? = ? THEN ? ELSE ? END",
              t.workflow_version_id,
              ^v.id,
              ^expr,
              ^acc
            )
          )
        end)

      direction = if sort["direction"] == "asc", do: :asc_nulls_last, else: :desc_nulls_last
      order_by(query, ^[{direction, value}, {:desc, :id}])
    else
      from t in query, order_by: [desc: t.id]
    end
  end

  def order(query, _, _, _, _), do: from(t in query, order_by: [desc: t.id])

  def metadata(query, scope, versions, key) when is_binary(key) do
    refs =
      Enum.flat_map(versions, fn v -> (view(v, key) || %{})["filters"] || [] end)
      |> Enum.uniq()
      |> Enum.take(10)

    options =
      Enum.flat_map(refs, fn ref ->
        value =
          Enum.reduce(versions, dynamic(fragment("NULL::jsonb")), fn v, acc ->
            spec = view(v, key)

            if spec && ref in (spec["filters"] || []) do
              expr = field_value(scope, v, ref)

              dynamic(
                [ticket: t],
                fragment(
                  "CASE WHEN ? = ? THEN ? ELSE ? END",
                  t.workflow_version_id,
                  ^v.id,
                  ^expr,
                  ^acc
                )
              )
            else
              acc
            end
          end)

        present = dynamic(not is_nil(^value) and fragment("? <> 'null'::jsonb", ^value))

        values =
          Repo.all(
            from t in query,
              where: ^present,
              distinct: true,
              order_by: fragment("1"),
              limit: 100,
              select: ^value
          )

        if values == [], do: [], else: [%{ref: ref, label: ref, values: values}]
      end)

    urgent =
      Enum.reduce(versions, dynamic(false), fn v, acc ->
        spec = view(v, key)

        if spec && spec["urgency"] do
          terminal = for stage <- v.definition["stages"], stage["terminal"], do: stage["key"]
          value = field_value(scope, v, spec["urgency"]["field"])
          highest = hd(spec["urgency"]["values"])

          dynamic(
            [ticket: t],
            ^acc or
              (t.workflow_version_id == ^v.id and t.stage not in ^terminal and
                 fragment("? = to_jsonb(?::text)", ^value, ^highest))
          )
        else
          acc
        end
      end)

    assignment =
      Enum.reduce(versions, dynamic(false), fn v, acc ->
        section = (view(v, key) || %{})["assignment_section"]

        if section do
          rule = assignment_permission(scope, v, section)
          dynamic([ticket: t], ^acc or (t.workflow_version_id == ^v.id and ^rule))
        else
          acc
        end
      end)

    %{
      filters: options,
      urgent: Repo.aggregate(where(query, ^urgent), :count),
      assignment?: Repo.exists?(where(query, ^assignment))
    }
  end

  def metadata(_, _, _, _), do: %{filters: [], urgent: 0, assignment?: false}

  def assignment_permission(scope, version, section_key) do
    section = Enum.find(version.definition["sections"], &(&1["key"] == section_key))

    if section && section["assignment"] do
      Enum.reduce(
        section["assignment"]["managers"],
        PolicyQuery.section(scope, version, section),
        fn actor, acc ->
          rule = PolicyQuery.actor(scope, version, actor)
          dynamic(^acc or ^rule)
        end
      )
    else
      dynamic(false)
    end
  end

  defp assignment_filter(query, _, _, _, input) when input in [nil, ""], do: query

  defp assignment_filter(query, scope, versions, key, input) do
    rule =
      Enum.reduce(versions, dynamic(false), fn v, acc ->
        spec = view(v, key)
        section = spec && spec["assignment_section"]

        if section && input in ["me", "unassigned"] do
          permission = assignment_permission(scope, v, section)

          assignments =
            from a in Instantflow.Collaboration.Assignment,
              where: a.ticket_id == parent_as(:ticket).id and a.section_key == ^section

          match =
            if input == "me",
              do:
                dynamic(exists(subquery(where(assignments, [a], a.membership_id == ^scope.id)))),
              else: dynamic(not exists(subquery(assignments)))

          dynamic(
            [ticket: t],
            ^acc or (t.workflow_version_id == ^v.id and ^permission and ^match)
          )
        else
          acc
        end
      end)

    where(query, ^rule)
  end

  defp urgency_rank(scope, v, key) do
    spec = view(v, key)["urgency"]

    if spec do
      value = field_value(scope, v, spec["field"])

      spec["values"]
      |> Enum.with_index()
      |> Enum.reduce(dynamic(fragment("to_jsonb(999)")), fn {label, rank}, acc ->
        dynamic(
          fragment(
            "CASE WHEN ? = to_jsonb(?::text) THEN to_jsonb(?::int) ELSE ? END",
            ^value,
            ^label,
            ^rank,
            ^acc
          )
        )
      end)
    else
      dynamic(fragment("NULL::jsonb"))
    end
  end

  defp field_value(scope, version, ref, normalize? \\ false) do
    [section_key, field_key] = String.split(ref, ".")
    section = Enum.find(version.definition["sections"], &(&1["key"] == section_key))

    if section do
      permission = PolicyQuery.section(scope, version, section)

      raw =
        dynamic(
          [ticket: t],
          fragment(
            "(SELECT s.values -> ? FROM ticket_sections s WHERE s.ticket_id = ? AND s.key = ?)",
            ^field_key,
            t.id,
            ^section_key
          )
        )

      value =
        if normalize? && Definition.fields(version.definition)[ref]["type"] == "datetime",
          do:
            dynamic(
              fragment(
                "to_jsonb(to_char((? #>> '{}')::timestamptz AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.US'))",
                ^raw
              )
            ),
          else: raw

      dynamic(fragment("CASE WHEN ? THEN ? ELSE NULL::jsonb END", ^permission, ^value))
    else
      dynamic(fragment("NULL::jsonb"))
    end
  end

  defp cast(type, value) when type in ~w(integer money) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> value
    end
  end

  defp cast("boolean", "true"), do: true
  defp cast("boolean", "false"), do: false
  defp cast(_, value), do: value
end
