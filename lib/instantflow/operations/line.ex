defmodule Instantflow.Operations.Line do
  use Ecto.Schema

  schema "fulfillment_lines" do
    field :organization_id, :integer
    field :workflow_id, :integer
    field :batch_id, :integer
    field :product_id, :integer
    field :name, :string
    field :unit_price, :integer
    field :quantity, :integer
    field :notes, :string
  end
end
