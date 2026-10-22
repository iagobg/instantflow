defmodule Instantflow.Operations.Resource do
  use Ecto.Schema

  schema "service_resources" do
    field :organization_id, :integer
    field :workflow_id, :integer
    field :name, :string
  end
end
