defmodule Instantflow.Identity.Department do
  use Ecto.Schema

  schema "departments" do
    field :name, :string
    belongs_to :organization, Instantflow.Identity.Organization
    timestamps(type: :utc_datetime)
  end
end
