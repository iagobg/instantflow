defmodule Instantflow.WorkflowCatalog.TemplateEvent do
  use Ecto.Schema

  schema "template_events" do
    field :operation, :string
    field :revision, :integer
    field :details, :map
    belongs_to :organization, Instantflow.Identity.Organization
    belongs_to :draft, Instantflow.WorkflowCatalog.Draft
    belongs_to :actor, Instantflow.Identity.User
    timestamps(type: :utc_datetime)
  end
end
