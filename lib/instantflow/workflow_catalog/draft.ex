defmodule Instantflow.WorkflowCatalog.Draft do
  use Ecto.Schema

  schema "workflow_drafts" do
    field :definition, :map
    field :bindings, :map, default: %{"roles" => %{}, "departments" => %{}}
    field :revision, :integer, default: 1
    field :source_digest, :string
    belongs_to :workflow, Instantflow.WorkflowCatalog.Workflow
    belongs_to :base_version, Instantflow.WorkflowCatalog.Version
    belongs_to :published_version, Instantflow.WorkflowCatalog.Version
    belongs_to :organization, Instantflow.Identity.Organization
    belongs_to :created_by, Instantflow.Identity.User
    belongs_to :updated_by, Instantflow.Identity.User
    timestamps(type: :utc_datetime)
  end
end
