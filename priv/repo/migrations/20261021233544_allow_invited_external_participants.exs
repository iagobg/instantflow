defmodule Instantflow.Repo.Migrations.AllowInvitedExternalParticipants do
  use Ecto.Migration

  def up do
    for table <- ~w(memberships invitations) do
      execute "ALTER TABLE #{table} DROP CONSTRAINT valid_role"

      execute "ALTER TABLE #{table} ADD CONSTRAINT valid_role CHECK (role IN ('admin','staff','parent','external'))"
    end
  end

  def down,
    do: raise("External participant memberships are forward-only; restore a coordinated backup.")
end
