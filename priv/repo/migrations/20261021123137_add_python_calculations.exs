defmodule Instantflow.Repo.Migrations.AddPythonCalculations do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE membership_grants DROP CONSTRAINT registered_role"

    execute "ALTER TABLE membership_grants ADD CONSTRAINT registered_role CHECK (role IN ('teacher','admissions','head','finance','finance_allocator','finance_reverser','operations','it','dean','counselor','python_author','python_reviewer','python_binder','python_execute','python_source'))"

    create table(:calculation_switch, primary_key: false) do
      add :id, :integer, primary_key: true
      add :enabled, :boolean, null: false, default: false
      add :generation, :bigint, null: false, default: 1
    end

    execute "INSERT INTO calculation_switch (id, enabled, generation) VALUES (1, false, 1)"
    execute "GRANT SELECT ON calculation_switch TO instantflow_runtime"

    create table(:calculation_scripts) do
      add :organization_id, references(:organizations), null: false
      add :key, :text, null: false
      add :digest, :text, null: false
      add :source, :text, null: false
      add :runtime, :text, null: false
      add :input_schema, :map, null: false
      add :output_schema, :map, null: false
      add :fixtures, {:array, :map}, null: false
      add :allowed_roles, {:array, :text}, null: false
      add :author_id, references(:users), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:calculation_scripts, [:organization_id, :key, :digest])
    create unique_index(:calculation_scripts, [:id, :organization_id])

    create table(:calculation_reviews) do
      add :organization_id, references(:organizations), null: false
      add :script_id, :bigint, null: false
      add :enabled, :boolean, null: false, default: false
      add :generation, :bigint, null: false, default: 1
      add :verified, :boolean, null: false, default: false
      add :reviewer_id, references(:users)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:calculation_reviews, [:script_id])

    execute "ALTER TABLE calculation_reviews ADD CONSTRAINT calculation_review_tenant FOREIGN KEY (script_id, organization_id) REFERENCES calculation_scripts(id, organization_id)"

    create table(:calculation_runs) do
      add :organization_id, references(:organizations), null: false
      add :ticket_id, :bigint, null: false
      add :script_id, :bigint, null: false
      add :membership_id, :bigint, null: false
      add :action_key, :text, null: false
      add :spec, :map, null: false
      add :snapshot, :map, null: false
      add :revisions, :map, null: false
      add :stage, :text, null: false
      add :stage_revision, :bigint, null: false
      add :generation, :bigint, null: false
      add :review_generation, :bigint, null: false
      add :status, :text, null: false, default: "queued"
      add :attempts, :integer, null: false, default: 0
      add :fence, :uuid
      add :lease_until, :utc_datetime_usec
      add :output, :map
      add :diagnostic, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:calculation_runs, [
             :organization_id,
             :ticket_id,
             :action_key,
             :stage_revision
           ])

    create unique_index(:calculation_runs, [:id, :organization_id])
    create index(:calculation_runs, [:organization_id, :status, :lease_until])

    for {field, target} <- [
          {"ticket_id", "tickets"},
          {"script_id", "calculation_scripts"},
          {"membership_id", "memberships"}
        ] do
      execute "ALTER TABLE calculation_runs ADD CONSTRAINT calculation_run_#{field}_tenant FOREIGN KEY (#{field}, organization_id) REFERENCES #{target}(id, organization_id)"
    end

    create constraint(:calculation_runs, :calculation_status,
             check:
               "status IN ('queued','running','succeeded','failed','timed_out','cancelled','stale') AND attempts BETWEEN 0 AND 3"
           )

    create table(:calculation_attempts) do
      add :organization_id, references(:organizations), null: false
      add :run_id, :bigint, null: false
      add :fence, :uuid, null: false
      add :number, :integer, null: false
      add :result, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:calculation_attempts, [:run_id, :fence])

    execute "ALTER TABLE calculation_attempts ADD CONSTRAINT calculation_attempt_tenant FOREIGN KEY (run_id, organization_id) REFERENCES calculation_runs(id, organization_id)"

    for table <- ~w(calculation_scripts calculation_reviews calculation_runs calculation_attempts) do
      execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY"

      execute "CREATE POLICY tenant_isolation ON #{table} USING (organization_id = NULLIF(current_setting('instantflow.organization_id', true), '')::bigint) WITH CHECK (organization_id = NULLIF(current_setting('instantflow.organization_id', true), '')::bigint)"

      execute "CREATE TRIGGER immutable_organization BEFORE UPDATE ON #{table} FOR EACH ROW EXECUTE FUNCTION reject_organization_move()"

      execute "GRANT SELECT, INSERT, UPDATE, DELETE ON #{table} TO instantflow_runtime"
      execute "GRANT USAGE, SELECT ON SEQUENCE #{table}_id_seq TO instantflow_runtime"
    end

    for table <- ~w(calculation_scripts calculation_attempts) do
      execute "CREATE TRIGGER immutable_calculation_record BEFORE UPDATE OR DELETE ON #{table} FOR EACH ROW EXECUTE FUNCTION reject_immutable_change()"
    end
  end

  def down, do: raise("Calculation audit history is forward-only; restore a coordinated backup.")
end
