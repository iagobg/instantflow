defmodule Instantflow.WorkflowCatalog.Retirement do
  @moduledoc "Operator-classified historical versions are retained without reactivating obsolete commands."
  import Ecto.Query

  def retired?(id) do
    Instantflow.Repo.exists?(from r in "retired_workflow_versions", where: r.version_id == ^id)
  end

  def require_active!(id) do
    if retired?(id), do: Instantflow.Repo.rollback(:retired_version)
  end
end
