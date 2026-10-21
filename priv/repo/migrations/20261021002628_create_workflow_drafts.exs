defmodule Instantflow.Repo.Migrations.CreateWorkflowDrafts do
  use Ecto.Migration

  def up do
    create table(:workflow_drafts) do
      add :organization_id, references(:organizations), null: false
      add :workflow_id, :bigint, null: false
      add :base_version_id, :bigint
      add :published_version_id, :bigint
      add :definition, :map, null: false
      add :bindings, :map, null: false
      add :revision, :integer, null: false, default: 1
      add :source_digest, :text
      add :created_by_id, references(:users), null: false
      add :updated_by_id, references(:users), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:workflow_drafts, [:id, :organization_id])
    create index(:workflow_drafts, [:organization_id, :workflow_id])
    create constraint(:workflow_drafts, :positive_draft_revision, check: "revision > 0")

    create table(:template_events) do
      add :organization_id, references(:organizations), null: false
      add :draft_id, :bigint, null: false
      add :actor_id, references(:users), null: false
      add :operation, :text, null: false
      add :revision, :integer, null: false
      add :details, :map, null: false
      timestamps(type: :utc_datetime)
    end

    execute "ALTER TABLE workflow_drafts ADD CONSTRAINT draft_workflow_tenant FOREIGN KEY (workflow_id, organization_id) REFERENCES workflows(id, organization_id)"

    for column <- ~w(base_version_id published_version_id) do
      execute "ALTER TABLE workflow_drafts ADD CONSTRAINT draft_#{column}_tenant FOREIGN KEY (#{column}, organization_id) REFERENCES workflow_versions(id, organization_id)"

      execute "ALTER TABLE workflow_drafts ADD CONSTRAINT draft_#{column}_workflow FOREIGN KEY (#{column}, workflow_id) REFERENCES workflow_versions(id, workflow_id)"
    end

    execute "ALTER TABLE template_events ADD CONSTRAINT event_draft_tenant FOREIGN KEY (draft_id, organization_id) REFERENCES workflow_drafts(id, organization_id)"

    execute "CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON template_events FOR EACH ROW EXECUTE FUNCTION reject_immutable_change()"

    execute "CREATE TRIGGER immutable_organization BEFORE UPDATE ON workflow_drafts FOR EACH ROW EXECUTE FUNCTION reject_organization_move()"

    execute """
    CREATE FUNCTION protect_published_draft() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF OLD.published_version_id IS NOT NULL THEN
        RAISE EXCEPTION 'published drafts are immutable' USING ERRCODE = '23514';
      END IF;
      IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
      IF NEW.workflow_id IS DISTINCT FROM OLD.workflow_id OR NEW.base_version_id IS DISTINCT FROM OLD.base_version_id THEN
        RAISE EXCEPTION 'draft ancestry is immutable' USING ERRCODE = '23514';
      END IF;
      RETURN NEW;
    END; $$
    """

    execute "CREATE TRIGGER protect_draft BEFORE UPDATE OR DELETE ON workflow_drafts FOR EACH ROW EXECUTE FUNCTION protect_published_draft()"

    for table <- ~w(workflow_drafts template_events) do
      execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY"

      execute "CREATE POLICY tenant_isolation ON #{table} USING (organization_id = NULLIF(current_setting('instantflow.organization_id', true), '')::bigint) WITH CHECK (organization_id = NULLIF(current_setting('instantflow.organization_id', true), '')::bigint)"

      execute "GRANT SELECT, INSERT, UPDATE, DELETE ON #{table} TO instantflow_runtime"
      execute "GRANT USAGE, SELECT ON SEQUENCE #{table}_id_seq TO instantflow_runtime"
    end
  end

  def down, do: raise("Draft history is forward-only; restore a coordinated backup to roll back.")
end
