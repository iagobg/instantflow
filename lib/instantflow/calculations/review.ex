defmodule Instantflow.Calculations.Review do
  use Ecto.Schema

  schema "calculation_reviews" do
    field :organization_id, :integer
    field :script_id, :integer
    field :enabled, :boolean, default: false
    field :verified, :boolean, default: false
    field :generation, :integer, default: 1
    field :reviewer_id, :integer
    timestamps(type: :utc_datetime)
  end
end
