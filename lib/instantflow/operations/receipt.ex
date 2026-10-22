defmodule Instantflow.Operations.Receipt do
  use Ecto.Schema

  schema "operation_receipts" do
    field :organization_id, :integer
    field :workflow_id, :integer
    field :actor_id, :integer
    field :key, :string
    field :operation, :string
    field :digest, :binary
    field :result, :map
    field :reason, :string
    field :inserted_at, :utc_datetime
  end
end
