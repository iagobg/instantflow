defmodule Instantflow.Delivery.Message do
  use Ecto.Schema

  schema "outbox_messages" do
    field :key, :string
    field :kind, :string
    field :behavior, :string, default: "success"
    field :status, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :payload, :map, default: %{}
    field :recipient_membership_id, :integer
    field :authorized_membership_id, :integer
    belongs_to :retried_by, Instantflow.Identity.User
    belongs_to :ticket, Instantflow.WorkflowRuntime.Ticket
    belongs_to :event, Instantflow.WorkflowRuntime.Event
    belongs_to :organization, Instantflow.Identity.Organization
    timestamps(type: :utc_datetime)
  end
end
