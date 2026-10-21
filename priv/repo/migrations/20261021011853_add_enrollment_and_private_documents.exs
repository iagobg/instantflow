defmodule Instantflow.Repo.Migrations.AddEnrollmentAndPrivateDocuments do
  use Ecto.Migration

  def up do
    for table <- ~w(memberships invitations) do
      execute "ALTER TABLE #{table} DROP CONSTRAINT valid_role"

      execute "ALTER TABLE #{table} ADD CONSTRAINT valid_role CHECK (role IN ('admin', 'staff', 'parent'))"
    end

    create table(:enrollments) do
      add :organization_id, references(:organizations), null: false
      add :ticket_id, :bigint, null: false
      add :public_message, :text, null: false, default: ""
      timestamps(type: :utc_datetime)
    end

    create unique_index(:enrollments, [:id, :organization_id])
    create unique_index(:enrollments, [:ticket_id])

    execute "ALTER TABLE enrollments ADD CONSTRAINT enrollment_ticket_tenant FOREIGN KEY (ticket_id, organization_id) REFERENCES tickets(id, organization_id)"

    alter table(:invitations) do
      add :enrollment_id, :bigint
    end

    execute "ALTER TABLE invitations ADD CONSTRAINT invitation_enrollment_tenant FOREIGN KEY (enrollment_id, organization_id) REFERENCES enrollments(id, organization_id)"

    create table(:guardian_links) do
      add :organization_id, references(:organizations), null: false
      add :enrollment_id, :bigint, null: false
      add :membership_id, :bigint, null: false
      add :verified_by_id, references(:users)
      add :verified_at, :utc_datetime
      add :active, :boolean, null: false, default: true
      timestamps(type: :utc_datetime)
    end

    create unique_index(:guardian_links, [:enrollment_id, :membership_id])

    for {column, target} <- [{"enrollment_id", "enrollments"}, {"membership_id", "memberships"}] do
      execute "ALTER TABLE guardian_links ADD CONSTRAINT guardian_#{column}_tenant FOREIGN KEY (#{column}, organization_id) REFERENCES #{target}(id, organization_id)"
    end

    create table(:private_documents) do
      add :organization_id, references(:organizations), null: false
      add :ticket_id, :bigint, null: false
      add :section_key, :text, null: false
      add :field_key, :text, null: false
      add :object_key, :text, null: false
      add :filename, :text, null: false
      add :media_type, :text, null: false
      add :content, :binary, null: false
      add :sha256, :binary, null: false
      add :size, :integer, null: false
      add :status, :text, null: false, default: "quarantined"
      add :uploaded_by_id, references(:users), null: false
      add :reviewed_by_id, references(:users)
      add :expires_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:private_documents, [:object_key])
    create index(:private_documents, [:organization_id, :ticket_id])

    create constraint(:private_documents, :document_size,
             check: "size > 0 AND size <= 5242880 AND octet_length(content) <= 5242880"
           )

    create constraint(:private_documents, :document_status,
             check: "status IN ('quarantined', 'ready', 'rejected', 'deleted', 'expired')"
           )

    execute "ALTER TABLE private_documents ADD CONSTRAINT document_ticket_tenant FOREIGN KEY (ticket_id, organization_id) REFERENCES tickets(id, organization_id)"

    for table <- ~w(enrollments guardian_links private_documents) do
      execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY"

      execute "CREATE POLICY tenant_isolation ON #{table} USING (organization_id = NULLIF(current_setting('instantflow.organization_id', true), '')::bigint) WITH CHECK (organization_id = NULLIF(current_setting('instantflow.organization_id', true), '')::bigint)"

      execute "CREATE TRIGGER immutable_organization BEFORE UPDATE ON #{table} FOR EACH ROW EXECUTE FUNCTION reject_organization_move()"

      execute "GRANT SELECT, INSERT, UPDATE, DELETE ON #{table} TO instantflow_runtime"
      execute "GRANT USAGE, SELECT ON SEQUENCE #{table}_id_seq TO instantflow_runtime"
    end
  end

  def down,
    do: raise("Guardian and document history is forward-only; restore a coordinated backup.")
end
