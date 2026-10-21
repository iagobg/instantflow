defmodule Instantflow.Finance.Account do
  use Ecto.Schema

  schema "budget_accounts" do
    field :organization_id, :integer
    field :department_id, :integer
    field :name, :string
    field :allocated, :integer
    field :reserved, :integer
    field :spent, :integer
  end
end
