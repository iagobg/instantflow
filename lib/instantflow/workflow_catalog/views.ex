defmodule Instantflow.WorkflowCatalog.Views do
  @moduledoc "Configured views share the bounded, pinned and authorized runtime projection service."
  defdelegate options(actor, filters \\ %{}), to: Instantflow.WorkflowRuntime.Projections

  defdelegate discovery(actor, filters \\ %{}),
    to: Instantflow.WorkflowRuntime.Projections,
    as: :view_discovery

  defdelegate search(actor, workflow_id, key, filters \\ %{}),
    to: Instantflow.WorkflowRuntime.Projections,
    as: :view

  defdelegate board_workspace(actor, workflow_id),
    to: Instantflow.WorkflowRuntime.Projections

  defdelegate empty_board_discovery(actor, workflow_id, filters),
    to: Instantflow.WorkflowRuntime.Projections

  defdelegate board(actor, workflow_id, key, filters),
    to: Instantflow.WorkflowRuntime.StageBoards,
    as: :read
end
