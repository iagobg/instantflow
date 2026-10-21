defmodule Instantflow.Repo.Migrations.HardenCalculationControlPlane do
  use Ecto.Migration

  def up do
    execute """
    CREATE FUNCTION lock_calculation_switch() RETURNS TABLE(enabled boolean, generation bigint)
    LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
      SELECT enabled, generation FROM public.calculation_switch WHERE id = 1 FOR SHARE
    $$
    """

    execute "REVOKE ALL ON FUNCTION lock_calculation_switch() FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION lock_calculation_switch() TO instantflow_runtime"

    create table(:calculation_switch_events) do
      add :enabled, :boolean, null: false
      add :generation, :bigint, null: false
      add :operator, :text, null: false
      add :inserted_at, :utc_datetime, null: false
    end

    execute "CREATE TRIGGER immutable_switch_event BEFORE UPDATE OR DELETE ON calculation_switch_events FOR EACH ROW EXECUTE FUNCTION reject_immutable_change()"

    execute """
    CREATE FUNCTION protect_calculation_identity() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF ROW(NEW.organization_id, NEW.ticket_id, NEW.script_id, NEW.membership_id, NEW.action_key,
             NEW.spec, NEW.revisions, NEW.stage, NEW.stage_revision, NEW.generation, NEW.review_generation)
         IS DISTINCT FROM ROW(OLD.organization_id, OLD.ticket_id, OLD.script_id, OLD.membership_id, OLD.action_key,
             OLD.spec, OLD.revisions, OLD.stage, OLD.stage_revision, OLD.generation, OLD.review_generation) THEN
        RAISE EXCEPTION 'calculation identity is immutable';
      END IF;
      RETURN NEW;
    END $$
    """

    execute "CREATE TRIGGER immutable_calculation_identity BEFORE UPDATE ON calculation_runs FOR EACH ROW EXECUTE FUNCTION protect_calculation_identity()"
  end

  def down, do: raise("Calculation audit history is forward-only.")
end
