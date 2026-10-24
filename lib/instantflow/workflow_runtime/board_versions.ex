defmodule Instantflow.WorkflowRuntime.BoardVersions do
  @moduledoc false
  import Ecto.Query
  alias Instantflow.Repo
  alias Instantflow.WorkflowCatalog.{Version, Workspaces}
  alias Instantflow.WorkflowRuntime.{ConfiguredQueries, Projections, Ticket}

  @batch_size 25

  # Caller holds Tenant's fresh authorization gate. Only the selected publication
  # is subsequently loaded in full. Historical discovery transfers read-policy
  # declarations in keyset batches, never fields, stages or transition bodies.
  def discover(scope, workflow_id, key) do
    latest_id =
      Repo.one(
        from v in Workspaces.authorized_query(scope, :workspace),
          where: v.workflow_id == ^workflow_id,
          select: v.id
      )

    eligible = scan(scope, workflow_id, key, latest_id, nil, [])
    %{eligible: Enum.sort_by(eligible, &{&1.number, &1.id}, :desc), latest_id: latest_id}
  end

  defp scan(scope, workflow_id, key, latest_id, before_id, eligible) do
    versions = candidates(workflow_id, key, latest_id, before_id)

    visible =
      Enum.filter(versions, fn version ->
        view = ConfiguredQueries.view(version, key)
        view && view["type"] == "board" && Projections.visible_view?(scope, version, view)
      end)

    admitted =
      scope
      |> Projections.view_query(visible, key)
      |> distinct([ticket: t], t.workflow_version_id)
      |> select([ticket: t], t.workflow_version_id)
      |> Repo.all()
      |> MapSet.new()

    options =
      for version <- visible,
          version.id == latest_id or MapSet.member?(admitted, version.id),
          do: %{id: version.id, number: version.number}

    eligible = options ++ eligible

    if length(versions) == @batch_size do
      scan(scope, workflow_id, key, latest_id, List.last(versions).id, eligible)
    else
      eligible
    end
  end

  @doc false
  def candidates(workflow_id, key, latest_id, before_id) do
    populated =
      from t in Ticket,
        where:
          t.workflow_version_id == parent_as(:version).id and
            t.organization_id == parent_as(:version).organization_id

    query =
      from v in Version,
        as: :version,
        where: v.workflow_id == ^workflow_id,
        where: v.id == ^(latest_id || 0) or exists(subquery(populated)),
        order_by: [desc: v.id],
        limit: @batch_size

    query = if before_id, do: where(query, [v], v.id < ^before_id), else: query

    Repo.all(
      from v in query,
        select: %Version{
          id: v.id,
          number: v.number,
          organization_id: v.organization_id,
          workflow_id: v.workflow_id,
          bindings: v.bindings,
          definition:
            fragment(
              """
              jsonb_build_object(
                'creation', jsonb_build_object('roles', ?->'creation'->'roles'),
                'interface', jsonb_build_object(
                  'access', ?->'interface'->'access',
                  'pages', CASE WHEN jsonb_path_exists(?, '$.interface.pages[*].participant')
                    THEN '[{"participant":{}}]'::jsonb ELSE '[]'::jsonb END),
                'participants', (SELECT COALESCE(jsonb_agg(jsonb_build_object('key', p->'key')), '[]'::jsonb)
                  FROM jsonb_array_elements(COALESCE(?->'participants', '[]'::jsonb)) p),
                'sections', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                  'key', s->'key', 'access', s->'access', 'assignment', s->'assignment')), '[]'::jsonb)
                  FROM jsonb_array_elements(?->'sections') s),
                'views', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                  'key', w->'key', 'type', w->'type', 'columns', w->'columns',
                  'visibility_roles', w->'visibility_roles')), '[]'::jsonb)
                  FROM jsonb_array_elements(?->'views') w WHERE w->>'key' = ?))
              """,
              v.definition,
              v.definition,
              v.definition,
              v.definition,
              v.definition,
              v.definition,
              ^key
            )
        }
    )
  end
end
