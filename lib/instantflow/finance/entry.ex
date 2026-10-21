defmodule Instantflow.Finance.Entry do
  use Ecto.Schema

  schema "budget_entries" do
    field :organization_id, :integer
    field :account_id, :integer
    field :ticket_id, :integer
    field :actor_id, :integer
    field :operation, :string
    field :amount, :integer
    field :reason, :string
    field :key, :string
    field :inserted_at, :utc_datetime
  end
end
