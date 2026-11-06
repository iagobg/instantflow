defmodule Instantflow.HistoricalSchema do
  @moduledoc "Current-command fixture seeding followed by a genuine pre-S10 schema before forward migration."
  alias Instantflow.OperatorRepo

  def prepare_catalog_seed do
    # Temporary compatibility for current Tenant reads while seeding old schemas.
    # Removed before the real forward migration; never masks backfill coverage.
    OperatorRepo.query!(
      "CREATE TABLE workflow_catalog_generations (organization_id bigint PRIMARY KEY, generation bigint NOT NULL DEFAULT 0)"
    )

    OperatorRepo.query!("GRANT SELECT ON workflow_catalog_generations TO instantflow_runtime")
  end

  def finish_catalog_seed do
    %{rows: [[0]]} = OperatorRepo.query!("SELECT count(*) FROM workflow_catalog_generations")
    OperatorRepo.query!("DROP TABLE workflow_catalog_generations")
  end

  def prepare_seed do
    prepare_catalog_seed()

    OperatorRepo.query!(
      "CREATE TABLE retired_workflow_versions (version_id bigint PRIMARY KEY, organization_id bigint, reason text, inserted_at timestamp)"
    )

    OperatorRepo.query!("GRANT SELECT ON retired_workflow_versions TO instantflow_runtime")

    OperatorRepo.query!(
      "ALTER TABLE transition_events ADD COLUMN details jsonb NOT NULL DEFAULT '{}'"
    )

    OperatorRepo.query!(
      "ALTER TABLE outbox_messages ADD COLUMN payload jsonb NOT NULL DEFAULT '{}', ADD COLUMN recipient_membership_id bigint, ADD COLUMN authorized_membership_id bigint"
    )
  end

  def finish_seed do
    finish_catalog_seed()
    %{rows: [[0]]} = OperatorRepo.query!("SELECT count(*) FROM retired_workflow_versions")
    OperatorRepo.query!("DROP TABLE retired_workflow_versions")
    # All seed metadata must be historical empty defaults before stripping the
    # temporary client-compatibility columns; no authored data may be discarded.
    %{rows: [[0]]} =
      OperatorRepo.query!("SELECT count(*) FROM transition_events WHERE details <> '{}'::jsonb")

    %{rows: [[0]]} =
      OperatorRepo.query!(
        "SELECT count(*) FROM outbox_messages WHERE payload <> '{}'::jsonb OR recipient_membership_id IS NOT NULL OR authorized_membership_id IS NOT NULL"
      )

    OperatorRepo.query!("ALTER TABLE transition_events DROP COLUMN details")

    OperatorRepo.query!(
      "ALTER TABLE outbox_messages DROP COLUMN payload, DROP COLUMN recipient_membership_id, DROP COLUMN authorized_membership_id"
    )
  end

  def legacy_snapshot(tables) do
    Map.new(
      tables,
      &{&1,
       OperatorRepo.query!(
         "SELECT to_jsonb(t) - 'details' - 'payload' - 'recipient_membership_id' - 'authorized_membership_id' FROM #{&1} t ORDER BY id"
       ).rows}
    )
  end

  def assert_defaults do
    # Populated forward migration must backfill every tenant's catalog token.
    %{rows: [[0]]} =
      OperatorRepo.query!("""
      SELECT count(*) FROM (
        SELECT organization_id, count(*) AS versions FROM workflow_versions GROUP BY organization_id
      ) v FULL JOIN workflow_catalog_generations g USING (organization_id)
      WHERE g.generation IS DISTINCT FROM v.versions
      """)

    %{rows: [[0]]} =
      OperatorRepo.query!("SELECT count(*) FROM transition_events WHERE details <> '{}'::jsonb")

    %{rows: [[0]]} =
      OperatorRepo.query!(
        "SELECT count(*) FROM outbox_messages WHERE payload <> '{}'::jsonb OR recipient_membership_id IS NOT NULL OR authorized_membership_id IS NOT NULL"
      )

    :ok
  end
end
