defmodule Instantflow.WorkflowRuntime.RecordRead do
  @moduledoc false
  import Ecto.Query
  alias Instantflow.{Repo, Tenant}
  alias Instantflow.WorkflowCatalog.Version
  alias Instantflow.WorkflowRuntime.{AccessFacts, Policy, Ticket}

  def fetch!(context, id) do
    {ticket, version, _facts} = snapshot!(context, id)
    {ticket, version}
  end

  def facts!(context, id) do
    {_ticket, _version, facts} = snapshot!(context, id)
    facts
  end

  defp snapshot!(context, id) do
    Tenant.context_fetch!(context, {__MODULE__, id}, fn scope ->
      # Keep ticket/section projections stable across their component queries,
      # while allowing other readers to hold the same snapshot boundary.
      ticket =
        from(t in Ticket, where: t.id == ^id)
        |> Tenant.lock_for_read()
        |> Repo.one()

      unless ticket, do: Repo.rollback(:not_found)
      version = Repo.get!(Version, ticket.workflow_version_id)
      facts = Map.fetch!(AccessFacts.load([scope], ticket, version), scope.id)
      unless Policy.discover?(scope, ticket, version, facts), do: Repo.rollback(:not_found)
      {ticket, version, facts}
    end)
  end
end
