defmodule Instantflow.Repo.Migrations.RetireSyntheticLegacyExecution do
  use Ecto.Migration

  def up do
    create table(:retired_workflow_versions, primary_key: false) do
      add :version_id, :bigint, primary_key: true
      add :organization_id, :bigint, null: false
      add :reason, :text, null: false
      add :inserted_at, :utc_datetime, null: false
    end

    execute "ALTER TABLE retired_workflow_versions ADD CONSTRAINT retired_version_tenant_fk FOREIGN KEY (version_id, organization_id) REFERENCES workflow_versions(id, organization_id)"

    # The transaction restores FORCE RLS before this operator-only audit is visible.
    for table <-
          ~w(workflow_versions tickets outbox_messages calculation_runs organization_events) do
      execute "ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY"
    end

    execute """
    INSERT INTO retired_workflow_versions(version_id,organization_id,reason,inserted_at)
    SELECT v.id,v.organization_id,'D-32: synthetic legacy execution retired; history retained',now()
    FROM workflow_versions v WHERE
      jsonb_path_exists(v.definition, '$.sections[*].access[*] ? (@.scope == "guardian")') OR
      jsonb_path_exists(v.definition, '$.transitions[*].actors[*] ? (@.scope == "guardian")') OR
      jsonb_path_exists(v.definition, '$.sections[*].fields[*] ? (@.type == "attachment" && !exists(@.document_policy))') OR
      (v.definition->'capabilities' ? 'operations' AND v.definition#>'{interface,operations}' IS NULL) OR
      EXISTS (
        SELECT FROM jsonb_array_elements(v.definition->'transitions') edge,
          jsonb_array_elements(v.definition->'stages') stage
        WHERE edge#>>'{finance,operation}'='release' AND edge->'reset' IS NULL
          AND stage->>'initial'='true' AND stage->>'key'=edge->>'to'
      )
    """

    execute """
    INSERT INTO organization_events(organization_id,operation,operator,key,inserted_at,updated_at)
    SELECT organization_id,'legacy_execution_retired','sprint11-retirement',
      'retired-version:' || version_id::text,now(),now() FROM retired_workflow_versions
    """

    execute """
    INSERT INTO organization_events(organization_id,operation,operator,key,inserted_at,updated_at)
    SELECT m.organization_id,'retired_delivery_cancelled','sprint11-retirement',
      'retired-message:' || m.id::text,now(),now()
    FROM outbox_messages m JOIN tickets t ON t.id=m.ticket_id
    JOIN retired_workflow_versions r ON r.version_id=t.workflow_version_id
    WHERE m.status IN ('pending','failed','ambiguous')
    """

    execute """
    UPDATE outbox_messages m SET status='cancelled'
    FROM tickets t JOIN retired_workflow_versions r ON r.version_id=t.workflow_version_id
    WHERE m.ticket_id=t.id AND m.status IN ('pending','failed','ambiguous')
    """

    execute """
    INSERT INTO organization_events(organization_id,operation,operator,key,inserted_at,updated_at)
    SELECT c.organization_id,'retired_calculation_cancelled','sprint11-retirement',
      'retired-calculation:' || c.id::text,now(),now()
    FROM calculation_runs c JOIN tickets t ON t.id=c.ticket_id
    JOIN retired_workflow_versions r ON r.version_id=t.workflow_version_id
    WHERE c.status IN ('queued','running')
    """

    execute """
    UPDATE calculation_runs c SET status='cancelled'
    FROM tickets t JOIN retired_workflow_versions r ON r.version_id=t.workflow_version_id
    WHERE c.ticket_id=t.id AND c.status IN ('queued','running')
    """

    execute "DROP TRIGGER synchronize_participant ON guardian_links"
    execute "DROP FUNCTION sync_guardian_participant()"

    execute "REVOKE INSERT, UPDATE, DELETE ON enrollments, guardian_links FROM instantflow_runtime"

    for table <-
          ~w(workflow_versions tickets outbox_messages calculation_runs organization_events) do
      execute "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY"
    end

    execute "ALTER TABLE retired_workflow_versions ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE retired_workflow_versions FORCE ROW LEVEL SECURITY"

    execute "CREATE POLICY tenant_isolation ON retired_workflow_versions USING (organization_id = NULLIF(current_setting('instantflow.organization_id', true), '')::bigint)"

    execute "GRANT SELECT ON retired_workflow_versions TO instantflow_runtime"
  end

  def down, do: raise("Legacy retirement is forward-only; restore a coordinated backup.")
end
