defmodule Instantflow.Repo.Migrations.BackfillGuardianParticipantRelationships do
  use Ecto.Migration

  def up do
    alter table(:ticket_participants), do: add(:legacy_guardian_link_id, :bigint)
    create unique_index(:guardian_links, [:id, :organization_id])
    create unique_index(:ticket_participants, [:legacy_guardian_link_id])

    execute "ALTER TABLE ticket_participants ADD CONSTRAINT participant_legacy_guardian_tenant FOREIGN KEY (legacy_guardian_link_id, organization_id) REFERENCES guardian_links(id, organization_id)"

    drop constraint(:ticket_participants, :participant_state)

    create constraint(:ticket_participants, :participant_state,
             check:
               "revision > 0 AND relationship ~ '^[a-z][a-z0-9_]{0,63}$' AND ((status = 'verified' AND verified_at IS NOT NULL AND (verified_by_id IS NOT NULL OR legacy_guardian_link_id IS NOT NULL)) OR (status IN ('pending', 'revoked') AND verified_at IS NULL))"
           )

    create constraint(:ticket_participants, :participant_legacy_kind,
             check: "legacy_guardian_link_id IS NULL OR relationship = 'legacy_guardian'"
           )

    execute """
    CREATE OR REPLACE FUNCTION reject_participant_move() RETURNS trigger LANGUAGE plpgsql AS '
    BEGIN
      IF (NEW.organization_id, NEW.workflow_id, NEW.ticket_id, NEW.membership_id, NEW.relationship, NEW.legacy_guardian_link_id)
         IS DISTINCT FROM
         (OLD.organization_id, OLD.workflow_id, OLD.ticket_id, OLD.membership_id, OLD.relationship, OLD.legacy_guardian_link_id)
      THEN RAISE EXCEPTION ''Participant ownership is immutable''; END IF;
      RETURN NEW;
    END'
    """

    # Serialize the backfill against legacy invitation/verification writes.
    # The migration transaction restores FORCE RLS before becoming visible.
    execute "LOCK TABLE guardian_links IN SHARE ROW EXCLUSIVE MODE"
    execute "ALTER TABLE ticket_participants NO FORCE ROW LEVEL SECURITY"

    execute """
    INSERT INTO ticket_participants
      (organization_id, workflow_id, ticket_id, membership_id, relationship, status,
       revision, verified_at, verified_by_id, legacy_guardian_link_id, inserted_at, updated_at)
    SELECT g.organization_id, t.workflow_id, t.id, g.membership_id, 'legacy_guardian',
      CASE WHEN NOT g.active THEN 'revoked' WHEN g.verified_at IS NOT NULL THEN 'verified' ELSE 'pending' END,
      1, CASE WHEN g.active THEN g.verified_at END, g.verified_by_id, g.id, g.inserted_at, g.updated_at
    FROM guardian_links g
    JOIN enrollments e ON e.id=g.enrollment_id AND e.organization_id=g.organization_id
    JOIN tickets t ON t.id=e.ticket_id AND t.organization_id=e.organization_id
    """

    execute """
    INSERT INTO organization_events(organization_id,actor_id,operation,operator,key,inserted_at,updated_at)
    SELECT organization_id,verified_by_id,'legacy_relationship_mapped','sprint09-backfill',
      'guardian-mapping:' || legacy_guardian_link_id::text || ':1',now(),now()
    FROM ticket_participants WHERE legacy_guardian_link_id IS NOT NULL
    """

    execute "ALTER TABLE ticket_participants FORCE ROW LEVEL SECURITY"

    execute """
    CREATE FUNCTION sync_guardian_participant() RETURNS trigger LANGUAGE plpgsql AS '
    DECLARE mapped_id bigint; mapped_revision integer;
    BEGIN
      IF TG_OP = ''UPDATE'' THEN
        IF (NEW.organization_id, NEW.enrollment_id, NEW.membership_id)
           IS DISTINCT FROM (OLD.organization_id, OLD.enrollment_id, OLD.membership_id)
        THEN RAISE EXCEPTION ''Guardian relationship ownership is immutable''; END IF;
      END IF;
      INSERT INTO ticket_participants AS r
        (organization_id,workflow_id,ticket_id,membership_id,relationship,status,revision,
         verified_at,verified_by_id,legacy_guardian_link_id,inserted_at,updated_at)
      SELECT NEW.organization_id,t.workflow_id,t.id,NEW.membership_id,''legacy_guardian'',
        CASE WHEN NOT NEW.active THEN ''revoked'' WHEN NEW.verified_at IS NOT NULL THEN ''verified'' ELSE ''pending'' END,
        1,CASE WHEN NEW.active THEN NEW.verified_at END,NEW.verified_by_id,NEW.id,NEW.inserted_at,NEW.updated_at
      FROM enrollments e JOIN tickets t ON t.id=e.ticket_id AND t.organization_id=e.organization_id
      WHERE e.id=NEW.enrollment_id AND e.organization_id=NEW.organization_id
      ON CONFLICT (legacy_guardian_link_id) DO UPDATE SET
        status=EXCLUDED.status,verified_at=EXCLUDED.verified_at,verified_by_id=EXCLUDED.verified_by_id,
        revision=r.revision+1,updated_at=EXCLUDED.updated_at
      WHERE (r.status,r.verified_at,r.verified_by_id)
        IS DISTINCT FROM (EXCLUDED.status,EXCLUDED.verified_at,EXCLUDED.verified_by_id)
      RETURNING id,revision INTO mapped_id,mapped_revision;
      IF mapped_id IS NOT NULL THEN
        INSERT INTO organization_events(organization_id,actor_id,operation,operator,key,inserted_at,updated_at)
        VALUES(NEW.organization_id,NEW.verified_by_id,''legacy_relationship_synchronized'',''legacy-bridge'',
          ''guardian-mapping:'' || NEW.id::text || '':'' || mapped_revision::text,now(),now());
      END IF;
      RETURN NEW;
    END'
    """

    execute "CREATE TRIGGER synchronize_participant AFTER INSERT OR UPDATE ON guardian_links FOR EACH ROW EXECUTE FUNCTION sync_guardian_participant()"
  end

  def down,
    do: raise("Guardian participant mappings are forward-only; restore a coordinated backup.")
end
