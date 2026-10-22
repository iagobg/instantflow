defmodule Instantflow.Repo.Migrations.AddProjectionAuditAndCuratedOutboxContracts do
  use Ecto.Migration

  def up do
    alter table(:transition_events), do: add(:details, :map, null: false, default: %{})

    alter table(:outbox_messages) do
      add :payload, :map, null: false, default: %{}
      add :recipient_membership_id, :bigint
      add :authorized_membership_id, :bigint
    end

    execute "ALTER TABLE outbox_messages ADD CONSTRAINT release_recipient_tenant_fk FOREIGN KEY (recipient_membership_id, organization_id) REFERENCES memberships(id, organization_id)"

    execute "ALTER TABLE outbox_messages ADD CONSTRAINT release_author_tenant_fk FOREIGN KEY (authorized_membership_id, organization_id) REFERENCES memberships(id, organization_id)"

    execute "ALTER TABLE outbox_messages DROP CONSTRAINT valid_status"

    execute "ALTER TABLE outbox_messages ADD CONSTRAINT valid_status CHECK (status IN ('pending','succeeded','failed','ambiguous','cancelled'))"

    execute """
    CREATE FUNCTION protect_release_snapshot() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF OLD.payload ? 'release' AND
        (OLD.payload IS DISTINCT FROM NEW.payload OR OLD.recipient_membership_id IS DISTINCT FROM NEW.recipient_membership_id OR
         OLD.authorized_membership_id IS DISTINCT FROM NEW.authorized_membership_id OR OLD.ticket_id <> NEW.ticket_id OR
         OLD.organization_id <> NEW.organization_id OR OLD.event_id <> NEW.event_id OR OLD.kind <> NEW.kind OR OLD.behavior <> NEW.behavior) THEN
        RAISE EXCEPTION 'immutable curated release snapshot' USING ERRCODE = '23514';
      END IF;
      RETURN NEW;
    END;
    $$
    """

    execute "CREATE TRIGGER immutable_release_snapshot BEFORE UPDATE ON outbox_messages FOR EACH ROW EXECUTE FUNCTION protect_release_snapshot()"
  end

  def down, do: raise("Audit and curated release history is forward-only.")
end
