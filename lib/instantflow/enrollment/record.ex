defmodule Instantflow.Enrollment.Record do
  use Ecto.Schema

  schema "enrollments" do
    field :public_message, :string, default: ""
    belongs_to :organization, Instantflow.Identity.Organization
    belongs_to :ticket, Instantflow.WorkflowRuntime.Ticket
    timestamps(type: :utc_datetime)
  end
end
