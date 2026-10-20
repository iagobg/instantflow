defmodule Instantflow.Repo.Migrations.CreateWorkflowRuntime do
  use Ecto.Migration

  def change do
    create table(:workflows) do
      add :organization_id, references(:organizations), null: false
      add :key, :text, null: false
      add :name, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:workflows, [:organization_id, :key])

    create table(:workflow_versions) do
      add :workflow_id, references(:workflows), null: false
      add :number, :integer, null: false
      add :definition, :map, null: false
      add :bindings, :map, null: false
      add :published_by_id, references(:users), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:workflow_versions, [:workflow_id, :number])
    create unique_index(:workflow_versions, [:id, :workflow_id])
    create constraint(:workflow_versions, :positive_number, check: "number > 0")

    create table(:tickets) do
      add :organization_id, references(:organizations), null: false
      add :workflow_id, references(:workflows), null: false

      add :workflow_version_id, references(:workflow_versions, with: [workflow_id: :workflow_id]),
        null: false

      add :requester_id, references(:users), null: false

      add :assigned_department_id,
          references(:departments, with: [organization_id: :organization_id]), null: false

      add :stage, :text, null: false
      add :return_stage, :text
      add :revision, :integer, null: false, default: 1
      add :stage_revision, :integer, null: false, default: 1
      timestamps(type: :utc_datetime)
    end

    create constraint(:tickets, :positive_revision, check: "revision > 0")
    create index(:tickets, [:requester_id])
    create index(:tickets, [:assigned_department_id, :stage])

    create table(:ticket_sections) do
      add :ticket_id, references(:tickets), null: false
      add :key, :text, null: false
      add :values, :map, null: false, default: %{}
      add :revision, :integer, null: false, default: 1
      timestamps(type: :utc_datetime)
    end

    create unique_index(:ticket_sections, [:ticket_id, :key])
    create constraint(:ticket_sections, :positive_revision, check: "revision > 0")

    create table(:transition_events) do
      add :ticket_id, references(:tickets), null: false
      add :actor_id, references(:users), null: false
      add :operation, :text, null: false
      add :from_stage, :text
      add :to_stage, :text, null: false
      add :reason, :text
      add :revision, :integer, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:transition_events, [:ticket_id, :revision])

    create table(:command_receipts) do
      add :actor_id, references(:users), null: false
      add :key, :text, null: false
      add :digest, :binary, null: false
      add :ticket_id, references(:tickets), null: false
      add :result, :map, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:command_receipts, [:actor_id, :key])

    create table(:outbox_messages) do
      add :ticket_id, references(:tickets), null: false
      add :event_id, references(:transition_events), null: false
      add :key, :text, null: false
      add :kind, :text, null: false
      add :behavior, :text, null: false, default: "success"
      add :status, :text, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :retried_by_id, references(:users)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:outbox_messages, [:key])
    create index(:outbox_messages, [:status, :id])

    create constraint(:outbox_messages, :valid_status,
             check: "status IN ('pending', 'succeeded', 'failed')"
           )

    create constraint(:outbox_messages, :valid_kind,
             check: "kind IN ('refresh', 'simulate_notification', 'simulate_provisioning')"
           )

    create constraint(:outbox_messages, :valid_behavior,
             check: "behavior IN ('success', 'fail_once', 'failure')"
           )

    create table(:delivery_attempts) do
      add :outbox_message_id, references(:outbox_messages), null: false
      add :number, :integer, null: false
      add :result, :text, null: false
      add :actor_id, references(:users)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:delivery_attempts, [:outbox_message_id, :number])

    execute """
            CREATE FUNCTION reject_immutable_change() RETURNS trigger LANGUAGE plpgsql AS $$
            BEGIN RAISE EXCEPTION 'immutable record' USING ERRCODE = '23514'; END;
            $$
            """,
            "DROP FUNCTION reject_immutable_change()"

    for table <- [
          "workflow_versions",
          "transition_events",
          "command_receipts",
          "delivery_attempts"
        ] do
      execute "CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON #{table} FOR EACH ROW EXECUTE FUNCTION reject_immutable_change()",
              "DROP TRIGGER immutable_record ON #{table}"
    end
  end
end
