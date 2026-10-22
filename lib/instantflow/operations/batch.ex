defmodule Instantflow.Operations.Batch do
  use Ecto.Schema

  schema "fulfillment_batches" do
    field :organization_id, :integer
    field :workflow_id, :integer
    field :session_id, :integer
    field :destination, :string
    field :kind, :string, default: "order"
    field :source_id, :integer
    field :status, :string, default: "pending"
    field :waiter, :string
    field :reason, :string
    field :print_count, :integer, default: 0
    field :inserted_at, :utc_datetime
  end
end
