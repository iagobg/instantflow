defmodule Instantflow.Repo.Migrations.AddLocalGrantsAndAuthorizationCoordination do
  use Ecto.Migration

  def up do
    # Development may check migration versions, but the runtime must never create schema tables.
    execute "GRANT SELECT ON schema_migrations TO instantflow_runtime"

    create table(:membership_grants) do
      add :organization_id, references(:organizations), null: false
      add :membership_id, :bigint, null: false
      add :department_id, :bigint, null: false
      add :role, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:membership_grants, [
             :organization_id,
             :membership_id,
             :department_id,
             :role
           ])

    create constraint(:membership_grants, :registered_role,
             check:
               "role IN ('teacher','admissions','head','finance','operations','it','dean','counselor')"
           )

    execute "ALTER TABLE membership_grants ADD CONSTRAINT grant_member_tenant FOREIGN KEY (membership_id, organization_id) REFERENCES memberships(id, organization_id)"

    execute "ALTER TABLE membership_grants ADD CONSTRAINT grant_department_tenant FOREIGN KEY (department_id, organization_id) REFERENCES departments(id, organization_id)"

    execute "CREATE TRIGGER immutable_organization BEFORE UPDATE ON membership_grants FOR EACH ROW EXECUTE FUNCTION reject_organization_move()"

    execute "ALTER TABLE membership_grants ENABLE ROW LEVEL SECURITY"

    execute "CREATE POLICY tenant_isolation ON membership_grants USING (organization_id = NULLIF(current_setting('instantflow.organization_id', true), '')::bigint) WITH CHECK (organization_id = NULLIF(current_setting('instantflow.organization_id', true), '')::bigint)"

    execute "GRANT SELECT, INSERT, UPDATE, DELETE ON membership_grants TO instantflow_runtime"
    execute "GRANT USAGE, SELECT ON SEQUENCE membership_grants_id_seq TO instantflow_runtime"
  end

  def down,
    do:
      raise(
        "Sprint 02 is forward-only. Restore a coordinated backup to roll back tenant permissions."
      )
end
