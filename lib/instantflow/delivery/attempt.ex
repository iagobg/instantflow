defmodule Instantflow.Delivery.Attempt do
  use Ecto.Schema

  schema "delivery_attempts" do
    field :number, :integer
    field :result, :string
    belongs_to :actor, Instantflow.Identity.User
    belongs_to :outbox_message, Instantflow.Delivery.Message
    belongs_to :organization, Instantflow.Identity.Organization
    timestamps(type: :utc_datetime)
  end
end
