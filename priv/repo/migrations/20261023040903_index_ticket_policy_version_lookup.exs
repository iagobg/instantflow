defmodule Instantflow.Repo.Migrations.IndexTicketPolicyVersionLookup do
  use Ecto.Migration

  def up do
    create index(:tickets, [:organization_id, :workflow_version_id])
  end

  def down, do: raise("Read-model indexing is forward-only; restore a coordinated backup.")
end
