defmodule Instantflow.Operations.Product do
  use Ecto.Schema

  schema "catalog_products" do
    field :organization_id, :integer
    field :workflow_id, :integer
    field :name, :string
    field :category, :string
    field :price, :integer
    field :destination, :string
    field :active, :boolean, default: true
    field :revision, :integer, default: 1
  end
end
