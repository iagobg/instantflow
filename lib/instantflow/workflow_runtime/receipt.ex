defmodule Instantflow.WorkflowRuntime.Receipt do
  use Ecto.Schema

  schema "command_receipts" do
    field :operation, :string
    field :key, :string
    field :digest, :binary, redact: true
    field :result, :map
    belongs_to :ticket, Instantflow.WorkflowRuntime.Ticket
    belongs_to :actor, Instantflow.Identity.User
    belongs_to :organization, Instantflow.Identity.Organization
    timestamps(type: :utc_datetime)
  end
end
