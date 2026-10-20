defmodule Instantflow.WorkflowCatalog.Workflow do
  use Ecto.Schema

  schema "workflows" do
    field :key, :string
    field :name, :string
    belongs_to :organization, Instantflow.Identity.Organization
    timestamps(type: :utc_datetime)
  end
end
