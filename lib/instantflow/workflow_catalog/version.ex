defmodule Instantflow.WorkflowCatalog.Version do
  use Ecto.Schema

  schema "workflow_versions" do
    field :number, :integer
    field :definition, :map
    field :bindings, :map
    belongs_to :workflow, Instantflow.WorkflowCatalog.Workflow
    belongs_to :published_by, Instantflow.Identity.User
    timestamps(type: :utc_datetime)
  end
end
