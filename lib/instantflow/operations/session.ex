defmodule Instantflow.Operations.Session do
  use Ecto.Schema

  schema "service_sessions" do
    field :organization_id, :integer
    field :workflow_id, :integer
    field :resource_id, :integer
    field :ticket_id, :integer
    field :resource_name, :string
    field :waiter, :string
    field :business_date, :date
    field :status, :string, default: "open"
    field :total, :integer, default: 0
    field :payment_method, :string
    field :opened_at, :utc_datetime
    field :settled_at, :utc_datetime
  end
end
