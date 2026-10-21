defmodule Instantflow.Repo.Migrations.AddSectionAssignments do
  use Ecto.Migration

  def up do
    create table(:section_assignments) do
      add :organization_id, references(:organizations), null: false
      add :ticket_id, :bigint, null: false
      add :section_key, :text, null: false
      add :membership_id, :bigint, null: false
    end

    create unique_index(:section_assignments, [:ticket_id, :section_key])

    execute "ALTER TABLE section_assignments ADD CONSTRAINT assignment_ticket_tenant FOREIGN KEY (ticket_id, organization_id) REFERENCES tickets(id, organization_id)"

    execute "ALTER TABLE section_assignments ADD CONSTRAINT assignment_member_tenant FOREIGN KEY (membership_id, organization_id) REFERENCES memberships(id, organization_id)"

    execute "ALTER TABLE section_assignments ENABLE ROW LEVEL SECURITY"

    execute "CREATE POLICY tenant_isolation ON section_assignments USING (organization_id = NULLIF(current_setting('instantflow.organization_id', true), '')::bigint) WITH CHECK (organization_id = NULLIF(current_setting('instantflow.organization_id', true), '')::bigint)"

    execute "CREATE TRIGGER immutable_organization BEFORE UPDATE ON section_assignments FOR EACH ROW EXECUTE FUNCTION reject_organization_move()"

    execute "GRANT SELECT, INSERT, UPDATE, DELETE ON section_assignments TO instantflow_runtime"
    execute "GRANT USAGE, SELECT ON SEQUENCE section_assignments_id_seq TO instantflow_runtime"
  end

  def down, do: raise("Assignments are forward-only; restore a coordinated backup.")
end
