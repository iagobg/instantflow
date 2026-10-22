defmodule Instantflow.Participants.Relationship do
  use Ecto.Schema

  schema "ticket_participants" do
    belongs_to :organization, Instantflow.Identity.Organization
    belongs_to :workflow, Instantflow.WorkflowCatalog.Workflow
    belongs_to :ticket, Instantflow.WorkflowRuntime.Ticket
    belongs_to :membership, Instantflow.Identity.Membership
    belongs_to :verified_by, Instantflow.Identity.User
    field :relationship, :string
    field :status, :string, default: "pending"
    field :revision, :integer, default: 1
    field :verified_at, :utc_datetime
    field :legacy_guardian_link_id, :integer
    timestamps(type: :utc_datetime)
  end
end
