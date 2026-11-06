defmodule Instantflow.WorkflowRuntime.RecordRead do
  @moduledoc false
  import Ecto.Query
  alias Instantflow.{Repo, Tenant}
  alias Instantflow.WorkflowCatalog.Version
  alias Instantflow.WorkflowRuntime.{Policy, Ticket}

  def fetch!(context, id) do
    Tenant.context_fetch!(context, {__MODULE__, id}, fn scope ->
      # The composite document projection retains its existing ticket lock.
      # Acquire it once, after the authorization locks and before business reads.
      ticket = Repo.one(from t in Ticket, where: t.id == ^id, lock: "FOR UPDATE")
      unless ticket, do: Repo.rollback(:not_found)
      version = Repo.get!(Version, ticket.workflow_version_id)
      unless Policy.discover?(scope, ticket, version), do: Repo.rollback(:not_found)
      {ticket, version}
    end)
  end
end
