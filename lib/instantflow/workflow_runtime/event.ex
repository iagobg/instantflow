defmodule Instantflow.WorkflowRuntime.Event do
  use Ecto.Schema

  schema "transition_events" do
    field :operation, :string
    field :from_stage, :string
    field :to_stage, :string
    field :reason, :string
    field :revision, :integer
    belongs_to :ticket, Instantflow.WorkflowRuntime.Ticket
    belongs_to :actor, Instantflow.Identity.User
    timestamps(type: :utc_datetime)
  end
end
