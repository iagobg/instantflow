defmodule Instantflow.Enrollment.Document do
  use Ecto.Schema

  schema "private_documents" do
    field :section_key, :string
    field :field_key, :string
    field :object_key, :string
    field :filename, :string
    field :media_type, :string
    field :content, :binary, redact: true
    field :sha256, :binary
    field :size, :integer
    field :status, :string, default: "quarantined"
    field :expires_at, :utc_datetime
    belongs_to :organization, Instantflow.Identity.Organization
    belongs_to :ticket, Instantflow.WorkflowRuntime.Ticket
    belongs_to :uploaded_by, Instantflow.Identity.User
    belongs_to :reviewed_by, Instantflow.Identity.User
    timestamps(type: :utc_datetime)
  end
end
