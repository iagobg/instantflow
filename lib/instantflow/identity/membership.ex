defmodule Instantflow.Identity.Membership do
  use Ecto.Schema

  schema "memberships" do
    field :role, :string, default: "staff"
    field :active, :boolean, default: true
    field :grants, {:array, :map}, virtual: true, default: []
    belongs_to :user, Instantflow.Identity.User
    belongs_to :organization, Instantflow.Identity.Organization
    belongs_to :department, Instantflow.Identity.Department
    timestamps(type: :utc_datetime)
  end
end
