defmodule Instantflow.Access.Grant do
  use Ecto.Schema

  schema "membership_grants" do
    field :organization_id, :integer
    field :membership_id, :integer
    field :department_id, :integer
    field :role, :string
    timestamps(type: :utc_datetime)
  end
end
