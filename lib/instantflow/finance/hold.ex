defmodule Instantflow.Finance.Hold do
  use Ecto.Schema

  schema "budget_holds" do
    field :organization_id, :integer
    field :account_id, :integer
    field :ticket_id, :integer
    field :amount, :integer
    field :status, :string
  end
end
