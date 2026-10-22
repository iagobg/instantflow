defmodule Instantflow.Repo.Migrations.AddScopedTicketParticipants do
  use Ecto.Migration

  def up do
    create table(:ticket_participants) do
      add :organization_id, references(:organizations), null: false
      add :workflow_id, :bigint, null: false
      add :ticket_id, :bigint, null: false
      add :membership_id, :bigint, null: false
      add :relationship, :text, null: false
      add :status, :text, null: false, default: "pending"
      add :revision, :integer, null: false, default: 1
      add :verified_at, :utc_datetime
      add :verified_by_id, references(:users)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:ticket_participants, [:ticket_id, :membership_id, :relationship])
    create index(:ticket_participants, [:organization_id, :membership_id, :ticket_id])

    execute "ALTER TABLE ticket_participants ADD CONSTRAINT participant_ticket_process FOREIGN KEY (ticket_id, organization_id, workflow_id) REFERENCES tickets(id, organization_id, workflow_id)"

    execute "ALTER TABLE ticket_participants ADD CONSTRAINT participant_membership_tenant FOREIGN KEY (membership_id, organization_id) REFERENCES memberships(id, organization_id)"

    create constraint(:ticket_participants, :participant_state,
             check:
               "revision > 0 AND relationship ~ '^[a-z][a-z0-9_]{0,63}$' AND ((status = 'verified' AND verified_at IS NOT NULL AND verified_by_id IS NOT NULL) OR (status IN ('pending', 'revoked') AND verified_at IS NULL))"
           )

    execute """
    CREATE FUNCTION reject_participant_move() RETURNS trigger LANGUAGE plpgsql AS '
    BEGIN
      IF (NEW.organization_id, NEW.workflow_id, NEW.ticket_id, NEW.membership_id, NEW.relationship)
         IS DISTINCT FROM
         (OLD.organization_id, OLD.workflow_id, OLD.ticket_id, OLD.membership_id, OLD.relationship)
      THEN RAISE EXCEPTION ''Participant ownership is immutable''; END IF;
      RETURN NEW;
    END'
    """

    execute "CREATE TRIGGER immutable_participant BEFORE UPDATE ON ticket_participants FOR EACH ROW EXECUTE FUNCTION reject_participant_move()"

    execute "ALTER TABLE ticket_participants ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE ticket_participants FORCE ROW LEVEL SECURITY"

    execute "CREATE POLICY tenant_isolation ON ticket_participants USING (organization_id = NULLIF(current_setting('instantflow.organization_id', true), '')::bigint) WITH CHECK (organization_id = NULLIF(current_setting('instantflow.organization_id', true), '')::bigint)"

    execute "GRANT SELECT, INSERT, UPDATE ON ticket_participants TO instantflow_runtime"
    execute "GRANT USAGE, SELECT ON SEQUENCE ticket_participants_id_seq TO instantflow_runtime"
  end

  def down, do: raise("Participant history is forward-only; restore a coordinated backup.")
end
