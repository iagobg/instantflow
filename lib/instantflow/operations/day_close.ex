defmodule Instantflow.Operations.DayClose do
  use Ecto.Schema

  schema "operation_day_closes" do
    field :organization_id, :integer
    field :workflow_id, :integer
    field :business_date, :date
    field :actor_id, :integer
    field :summary, :map
    field :inserted_at, :utc_datetime
  end
end
