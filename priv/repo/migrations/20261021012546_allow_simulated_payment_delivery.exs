defmodule Instantflow.Repo.Migrations.AllowSimulatedPaymentDelivery do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE outbox_messages DROP CONSTRAINT valid_kind"

    execute "ALTER TABLE outbox_messages ADD CONSTRAINT valid_kind CHECK (kind IN ('refresh', 'simulate_notification', 'simulate_provisioning', 'simulate_payment'))"
  end

  def down, do: raise("Simulated payment history is forward-only.")
end
