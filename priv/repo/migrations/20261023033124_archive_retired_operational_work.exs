defmodule Instantflow.Repo.Migrations.ArchiveRetiredOperationalWork do
  use Ecto.Migration

  def up do
    # A maintenance transaction gives retained unpaid work a non-live disposition.
    # The existing one_open_session_per_resource index then releases its occupancy.
    for table <-
          ~w(service_sessions fulfillment_batches tickets workflow_versions retired_workflow_versions organization_events outbox_messages calculation_runs) do
      execute "ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY"
    end

    # The oldest operational tickets predate capability declarations. Their
    # actual session lineage, not the absence of an optional capability alone,
    # establishes that a missing contract is retired operational execution.
    execute """
    WITH retired AS (
      INSERT INTO retired_workflow_versions(version_id,organization_id,reason,inserted_at)
      SELECT DISTINCT v.id,v.organization_id,
        'D-32: historical session without operational contract; history retained',now()
      FROM workflow_versions v JOIN tickets t ON t.workflow_version_id=v.id
      JOIN service_sessions s ON s.ticket_id=t.id
      WHERE v.definition#>'{interface,operations}' IS NULL
      ON CONFLICT (version_id) DO NOTHING RETURNING version_id,organization_id
    )
    INSERT INTO organization_events(organization_id,operation,operator,key,inserted_at,updated_at)
    SELECT organization_id,'legacy_execution_retired','sprint11-retirement',
      'retired-version:' || version_id::text,now(),now() FROM retired
    """

    execute """
    WITH cancelled AS (
      UPDATE outbox_messages m SET status='cancelled'
      FROM tickets t JOIN retired_workflow_versions r ON r.version_id=t.workflow_version_id
      WHERE m.ticket_id=t.id AND m.status IN ('pending','failed','ambiguous')
      RETURNING m.id,m.organization_id
    )
    INSERT INTO organization_events(organization_id,operation,operator,key,inserted_at,updated_at)
    SELECT organization_id,'retired_delivery_cancelled','sprint11-retirement',
      'retired-message:' || id::text,now(),now() FROM cancelled
    """

    execute """
    WITH cancelled AS (
      UPDATE calculation_runs c SET status='cancelled'
      FROM tickets t JOIN retired_workflow_versions r ON r.version_id=t.workflow_version_id
      WHERE c.ticket_id=t.id AND c.status IN ('queued','running')
      RETURNING c.id,c.organization_id
    )
    INSERT INTO organization_events(organization_id,operation,operator,key,inserted_at,updated_at)
    SELECT organization_id,'retired_calculation_cancelled','sprint11-retirement',
      'retired-calculation:' || id::text,now(),now() FROM cancelled
    """

    drop constraint(:service_sessions, :session_state)

    create constraint(:service_sessions, :session_state,
             check:
               "length(waiter) BETWEEN 1 AND 120 AND total >= 0 AND ((status IN ('open','archived') AND settled_at IS NULL AND payment_method IS NULL) OR (status = 'settled' AND settled_at IS NOT NULL AND payment_method IN ('cash','card','pix')))"
           )

    drop constraint(:fulfillment_batches, :batch_state)

    create constraint(:fulfillment_batches, :batch_state,
             check:
               "status IN ('pending','handed','cancelled','archived') AND print_count >= 0 AND ((kind = 'order' AND source_id IS NULL) OR (kind = 'cancellation' AND source_id IS NOT NULL AND length(reason) BETWEEN 1 AND 500))"
           )

    execute """
    INSERT INTO organization_events(organization_id,operation,operator,key,inserted_at,updated_at)
    SELECT s.organization_id,'retired_session_archived','sprint11-retirement',
      'retired-session:' || s.id::text,now(),now()
    FROM service_sessions s JOIN tickets t ON t.id=s.ticket_id
    JOIN retired_workflow_versions r ON r.version_id=t.workflow_version_id
    WHERE s.status='open'
    """

    execute """
    INSERT INTO organization_events(organization_id,operation,operator,key,inserted_at,updated_at)
    SELECT b.organization_id,'retired_batch_archived','sprint11-retirement',
      'retired-batch:' || b.id::text,now(),now()
    FROM fulfillment_batches b JOIN service_sessions s ON s.id=b.session_id
    JOIN tickets t ON t.id=s.ticket_id
    JOIN retired_workflow_versions r ON r.version_id=t.workflow_version_id
    WHERE b.status='pending'
    """

    execute """
    UPDATE fulfillment_batches b SET status='archived'
    FROM service_sessions s JOIN tickets t ON t.id=s.ticket_id
    JOIN retired_workflow_versions r ON r.version_id=t.workflow_version_id
    WHERE b.session_id=s.id AND b.status='pending'
    """

    execute """
    UPDATE service_sessions s SET status='archived'
    FROM tickets t JOIN retired_workflow_versions r ON r.version_id=t.workflow_version_id
    WHERE s.ticket_id=t.id AND s.status='open'
    """

    # Settlements, captured line amounts, cancellations, receipts and day snapshots
    # are untouched. Archived means neither paid nor manually handed off.
    for table <-
          ~w(service_sessions fulfillment_batches tickets workflow_versions retired_workflow_versions organization_events outbox_messages calculation_runs) do
      execute "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY"
    end
  end

  def down, do: raise("Operational archival is forward-only; restore a coordinated backup.")
end
