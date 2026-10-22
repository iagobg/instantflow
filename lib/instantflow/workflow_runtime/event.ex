defmodule Instantflow.WorkflowRuntime.Event do
  use Ecto.Schema

  schema "transition_events" do
    field :operation, :string
    field :from_stage, :string
    field :to_stage, :string
    field :reason, :string
    field :revision, :integer
    field :details, :map, default: %{}
    belongs_to :ticket, Instantflow.WorkflowRuntime.Ticket
    belongs_to :actor, Instantflow.Identity.User
    belongs_to :organization, Instantflow.Identity.Organization
    timestamps(type: :utc_datetime)
  end
end
