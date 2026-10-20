defmodule Instantflow.WorkflowRuntime.Section do
  use Ecto.Schema

  schema "ticket_sections" do
    field :key, :string
    field :values, :map, default: %{}
    field :revision, :integer, default: 1
    belongs_to :ticket, Instantflow.WorkflowRuntime.Ticket
    belongs_to :organization, Instantflow.Identity.Organization
    timestamps(type: :utc_datetime)
  end
end
