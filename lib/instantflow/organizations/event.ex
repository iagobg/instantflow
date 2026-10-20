defmodule Instantflow.Organizations.Event do
  use Ecto.Schema

  schema "organization_events" do
    field :operation, :string
    field :operator, :string
    field :key, :string
    belongs_to :organization, Instantflow.Identity.Organization
    belongs_to :actor, Instantflow.Identity.User
    timestamps(type: :utc_datetime)
  end
end
