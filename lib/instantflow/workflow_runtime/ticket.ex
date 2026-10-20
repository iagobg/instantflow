defmodule Instantflow.WorkflowRuntime.Ticket do
  use Ecto.Schema

  schema "tickets" do
    field :stage, :string
    field :return_stage, :string
    field :revision, :integer, default: 1
    field :stage_revision, :integer, default: 1
    belongs_to :organization, Instantflow.Identity.Organization
    belongs_to :workflow, Instantflow.WorkflowCatalog.Workflow
    belongs_to :workflow_version, Instantflow.WorkflowCatalog.Version
    belongs_to :requester, Instantflow.Identity.User
    belongs_to :assigned_department, Instantflow.Identity.Department
    has_many :sections, Instantflow.WorkflowRuntime.Section
    timestamps(type: :utc_datetime)
  end
end
