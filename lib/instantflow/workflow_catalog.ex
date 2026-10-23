defmodule Instantflow.WorkflowCatalog do
  @moduledoc "Publishes validated immutable definitions with local bindings. Publication grants no ticket access."
  import Ecto.Query
  alias Instantflow.{Identity, Repo, Tenant}
  alias Instantflow.WorkflowCatalog.{Definition, Version, Workflow}

  def publish(actor, definition, bindings, expected_version \\ 0) do
    Tenant.transaction(actor, &publish_scoped!(&1, definition, bindings, expected_version))
    |> notify_publication()
  end

  @doc "Internal authoring mutation; caller owns the tenant transaction and authorization gate."
  def publish_scoped!(actor, definition, bindings, expected_version) do
    actor = Identity.lock_scope!(actor)
    unless actor.role == "admin", do: Repo.rollback(:forbidden)

    case Definition.validate(definition) do
      :ok -> :ok
      {:error, errors} -> Repo.rollback({:invalid_definition, errors})
    end

    Instantflow.Calculations.Catalogue.validate_bindings!(actor, definition)

    unless valid_bindings?(definition, bindings, actor.organization_id),
      do: Repo.rollback(:invalid_bindings)

    Repo.query!("SELECT pg_advisory_xact_lock($1)", [actor.organization_id])

    workflow =
      Repo.one(
        from w in Workflow,
          where:
            w.organization_id == ^actor.organization_id and
              w.key == ^definition["template_key"],
          lock: "FOR UPDATE"
      ) ||
        Repo.insert!(%Workflow{
          organization_id: actor.organization_id,
          key: definition["template_key"],
          name: definition["name"]
        })

    latest =
      Repo.one(from v in Version, where: v.workflow_id == ^workflow.id, select: max(v.number)) ||
        0

    unless latest == expected_version, do: Repo.rollback(:conflict)

    if latest > 0 do
      previous = Repo.get_by!(Version, workflow_id: workflow.id, number: latest)

      if Instantflow.WorkflowCatalog.Workspaces.operational?(previous.definition) and
           !Instantflow.WorkflowCatalog.Workspaces.operational?(definition),
         do: Repo.rollback(:incompatible_workspace)
    end

    Repo.insert!(%Version{
      workflow_id: workflow.id,
      number: latest + 1,
      definition: definition,
      bindings: bindings,
      published_by_id: actor.user_id,
      organization_id: actor.organization_id
    })
  end

  @doc false
  def notify_publication(result) do
    case result do
      {:ok, version} ->
        Phoenix.PubSub.broadcast(
          Instantflow.PubSub,
          "organization:#{version.organization_id}",
          :workspaces_changed
        )

      _ ->
        :ok
    end

    result
  end

  def available(actor, filters \\ %{}) do
    Tenant.read(
      actor,
      fn fresh ->
        Instantflow.WorkflowCatalog.Workspaces.authorized_query(fresh, :creation)
        |> Instantflow.WorkflowCatalog.Workspaces.page(filters)
        |> Map.fetch!(:rows)
      end,
      []
    )
  end

  def creatable?(actor, workflow_id) do
    Tenant.read(
      actor,
      fn fresh ->
        Repo.exists?(
          from v in Instantflow.WorkflowCatalog.Workspaces.authorized_query(fresh, :creation),
            where: v.workflow_id == ^workflow_id
        )
      end,
      false
    )
  end

  def valid_bindings?(d, bindings, organization_id, mode \\ :complete),
    do: Instantflow.WorkflowCatalog.Bindings.valid?(d, bindings, organization_id, mode)
end
