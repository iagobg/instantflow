defmodule Instantflow.Repo.Migrations.AddWorkflowCatalogGenerations do
  use Ecto.Migration

  def up do
    create table(:workflow_catalog_generations, primary_key: false) do
      add :organization_id, references(:organizations), primary_key: true
      add :generation, :bigint, null: false, default: 0
    end

    # Block publication through backfill and trigger installation so no committed
    # version can escape the generation change. Ordinary readers can continue.
    execute "LOCK TABLE workflow_versions IN SHARE ROW EXCLUSIVE MODE"

    execute """
    INSERT INTO workflow_catalog_generations (organization_id, generation)
    SELECT organization_id, count(*) FROM workflow_versions GROUP BY organization_id
    """

    execute "ALTER TABLE workflow_catalog_generations ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE workflow_catalog_generations FORCE ROW LEVEL SECURITY"

    execute """
    CREATE POLICY tenant_isolation ON workflow_catalog_generations
    USING (organization_id = NULLIF(current_setting('instantflow.organization_id', true), '')::bigint)
    """

    execute "GRANT SELECT ON workflow_catalog_generations TO instantflow_runtime"

    # A separate row avoids upgrading Tenant's organization FOR SHARE lock.
    # The counter is transactional and works across application nodes and imports.
    execute """
    CREATE FUNCTION public.advance_workflow_catalog_generation()
    RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
    BEGIN
      INSERT INTO public.workflow_catalog_generations AS g (organization_id, generation)
      VALUES (NEW.organization_id, 1)
      ON CONFLICT (organization_id) DO UPDATE SET generation = g.generation + 1;
      RETURN NEW;
    END;
    $$
    """

    execute "REVOKE ALL ON FUNCTION public.advance_workflow_catalog_generation() FROM PUBLIC"

    execute """
    CREATE TRIGGER advance_catalog_generation AFTER INSERT ON workflow_versions
    FOR EACH ROW EXECUTE FUNCTION public.advance_workflow_catalog_generation()
    """
  end

  def down,
    do:
      raise(
        "Forward-only migration. Keep the additive generation table and trigger on code rollback."
      )
end
