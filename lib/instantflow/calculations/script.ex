defmodule Instantflow.Calculations.Script do
  use Ecto.Schema

  schema "calculation_scripts" do
    field :organization_id, :integer
    field :key, :string
    field :digest, :string
    field :source, :string
    field :runtime, :string
    field :input_schema, :map
    field :output_schema, :map
    field :fixtures, {:array, :map}
    field :allowed_roles, {:array, :string}
    field :author_id, :integer
    timestamps(type: :utc_datetime)
  end
end
