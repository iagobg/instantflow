defmodule Instantflow.Repo.Migrations.IndexRecipientMessageReads do
  use Ecto.Migration

  def change do
    create index(:outbox_messages, [:organization_id, :recipient_membership_id, :ticket_id, :id])
  end
end
