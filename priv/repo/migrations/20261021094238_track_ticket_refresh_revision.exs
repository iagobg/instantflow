defmodule Instantflow.Repo.Migrations.TrackTicketRefreshRevision do
  use Ecto.Migration

  def up do
    alter table(:tickets) do
      add :refreshed_revision, :bigint, null: false, default: 0
    end

    create constraint(:tickets, :refresh_revision_bounds,
             check: "refreshed_revision >= 0 AND refreshed_revision <= revision"
           )
  end

  def down, do: raise("Refresh checkpoints are forward-only; restore a coordinated backup.")
end
