defmodule Instantflow.Calculations.Attempt do
  use Ecto.Schema

  schema "calculation_attempts" do
    field :organization_id, :integer
    field :run_id, :integer
    field :fence, Ecto.UUID
    field :number, :integer
    field :result, :string
    timestamps(type: :utc_datetime_usec)
  end
end
