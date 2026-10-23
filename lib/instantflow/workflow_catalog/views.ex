defmodule Instantflow.WorkflowCatalog.Views do
  @moduledoc "Configured views share the bounded, pinned and authorized runtime projection service."
  defdelegate options(actor, filters \\ %{}), to: Instantflow.WorkflowRuntime.Projections

  defdelegate discovery(actor, filters \\ %{}),
    to: Instantflow.WorkflowRuntime.Projections,
    as: :view_discovery

  defdelegate search(actor, workflow_id, key, filters \\ %{}),
    to: Instantflow.WorkflowRuntime.Projections,
    as: :view
end
