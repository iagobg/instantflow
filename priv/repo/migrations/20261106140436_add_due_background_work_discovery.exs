defmodule Instantflow.OperatorRepo.Migrations.AddDueBackgroundWorkDiscovery do
  use Ecto.Migration

  def up do
    # The existing operator owns control-plane functions. FORCE RLS applies to
    # ordinary owners, so fail explicitly if this account cannot discover work.
    execute """
    DO $$ BEGIN
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname=current_user AND (rolsuper OR rolbypassrls)) THEN
        RAISE EXCEPTION 'Due-work discovery requires the privileged migration/operator account';
      END IF;
    END $$
    """

    execute """
    CREATE FUNCTION public.delivery_organizations(after_id bigint, batch_limit integer)
    RETURNS TABLE(id bigint) LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path = pg_catalog AS $$
      SELECT due.organization_id
      FROM (
        SELECT DISTINCT m.organization_id
        FROM public.outbox_messages m
        JOIN public.organizations o ON o.id=m.organization_id
        WHERE m.status='pending' AND o.status='active'
      ) due
      ORDER BY (due.organization_id <= COALESCE(after_id, 0)), due.organization_id
      LIMIT LEAST(GREATEST(COALESCE(batch_limit, 50), 1), 100)
    $$
    """

    execute """
    CREATE FUNCTION public.maintenance_organizations(after_id bigint, batch_limit integer)
    RETURNS TABLE(id bigint) LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path = pg_catalog AS $$
      SELECT due.organization_id
      FROM (
        SELECT d.organization_id
        FROM public.private_documents d
        JOIN public.tickets t ON t.id=d.ticket_id AND t.organization_id=d.organization_id
        WHERE d.status IN ('ready','quarantined') AND d.expires_at <= (now() AT TIME ZONE 'UTC')
          AND NOT EXISTS (SELECT FROM public.retired_workflow_versions r WHERE r.version_id=t.workflow_version_id)
        UNION
        SELECT c.organization_id
        FROM public.calculation_runs c
        JOIN public.tickets t ON t.id=c.ticket_id AND t.organization_id=c.organization_id
        WHERE c.status NOT IN ('queued','running') AND c.snapshot <> '{}'::jsonb
          AND c.inserted_at < (now() AT TIME ZONE 'UTC') - interval '7 days'
          AND NOT EXISTS (SELECT FROM public.retired_workflow_versions r WHERE r.version_id=t.workflow_version_id)
      ) due
      JOIN public.organizations o ON o.id=due.organization_id
      WHERE o.status='active'
      ORDER BY (due.organization_id <= COALESCE(after_id, 0)), due.organization_id
      LIMIT LEAST(GREATEST(COALESCE(batch_limit, 50), 1), 100)
    $$
    """

    for name <- ["delivery_organizations", "maintenance_organizations"] do
      execute "REVOKE ALL ON FUNCTION public.#{name}(bigint, integer) FROM PUBLIC"
      execute "GRANT EXECUTE ON FUNCTION public.#{name}(bigint, integer) TO instantflow_runtime"
    end
  end

  def down,
    do:
      raise(
        "Forward-only migration. Retain the additive functions when rolling back application code."
      )
end
