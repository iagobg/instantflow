defmodule Instantflow.HistoricalSchema do
  @moduledoc "Current-command fixture seeding followed by a genuine pre-S10 schema before forward migration."
  alias Instantflow.OperatorRepo

  def prepare_seed do
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
    %{rows: [[0]]} =
      OperatorRepo.query!("SELECT count(*) FROM transition_events WHERE details <> '{}'::jsonb")

    %{rows: [[0]]} =
      OperatorRepo.query!(
        "SELECT count(*) FROM outbox_messages WHERE payload <> '{}'::jsonb OR recipient_membership_id IS NOT NULL OR authorized_membership_id IS NOT NULL"
      )

    :ok
  end
end
