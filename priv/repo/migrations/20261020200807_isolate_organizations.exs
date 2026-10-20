defmodule Instantflow.Repo.Migrations.IsolateOrganizations do
  use Ecto.Migration

  @parents [
    {"workflow_versions", "workflows", "workflow_id"},
    {"ticket_sections", "tickets", "ticket_id"},
    {"transition_events", "tickets", "ticket_id"},
    {"command_receipts", "tickets", "ticket_id"},
    {"outbox_messages", "tickets", "ticket_id"},
    {"delivery_attempts", "outbox_messages", "outbox_message_id"}
  ]
  @tenant_tables ~w(departments memberships invitations workflows workflow_versions tickets ticket_sections transition_events command_receipts outbox_messages delivery_attempts organization_events)

  def up do
    drop constraint(:organizations, :single_organization)

    alter table(:organizations) do
      add :slug, :text
      add :status, :text, null: false, default: "active"
    end

    execute "UPDATE organizations SET slug = CASE WHEN id = 1 THEN 'horizonte' ELSE 'organization-' || id::text END"

    alter table(:organizations), do: modify(:slug, :text, null: false)
    create unique_index(:organizations, [:slug])
    create constraint(:organizations, :valid_status, check: "status IN ('active','suspended')")
    create constraint(:organizations, :valid_slug, check: "slug ~ '^[a-z][a-z0-9-]{1,62}$'")

    execute "SELECT setval(pg_get_serial_sequence('organizations', 'id'), COALESCE((SELECT max(id) FROM organizations), 1), EXISTS(SELECT 1 FROM organizations))"

    # A maintenance-window transaction controls append-only backfill; ordinary traffic never disables protection.
    for table <- ~w(workflow_versions transition_events command_receipts delivery_attempts),
        do: execute("ALTER TABLE #{table} DISABLE TRIGGER immutable_record")

    for {table, parent, fk} <- @parents do
      alter table(table), do: add(:organization_id, :bigint)

      execute "UPDATE #{table} AS child SET organization_id = parent.organization_id FROM #{parent} AS parent WHERE child.#{fk} = parent.id"

      alter table(table), do: modify(:organization_id, :bigint, null: false)
    end

    alter table(:command_receipts), do: add(:operation, :text)

    execute """
    UPDATE command_receipts r SET operation = CASE WHEN e.operation = 'create' THEN 'create'
      WHEN e.operation LIKE 'save:%' THEN 'save_section' ELSE 'transition' END
    FROM transition_events e WHERE e.ticket_id = r.ticket_id AND e.revision = (r.result->>'revision')::integer
    """

    alter table(:command_receipts), do: modify(:operation, :text, null: false)
    drop unique_index(:command_receipts, [:actor_id, :key])
    create unique_index(:command_receipts, [:organization_id, :actor_id, :operation, :key])

    for table <- ~w(workflow_versions transition_events command_receipts delivery_attempts),
        do: execute("ALTER TABLE #{table} ENABLE TRIGGER immutable_record")

    create table(:organization_events) do
      add :organization_id, references(:organizations), null: false
      add :actor_id, references(:users)
      add :operation, :text, null: false
      add :operator, :text
      add :key, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:organization_events, [:organization_id, :key])

    execute "CREATE TRIGGER immutable_record BEFORE UPDATE OR DELETE ON organization_events FOR EACH ROW EXECUTE FUNCTION reject_immutable_change()"

    for table <- @tenant_tables do
      create unique_index(table, [:id, :organization_id],
               name: String.to_atom("#{table}_tenant_identity")
             )

      execute "ALTER TABLE #{table} ADD CONSTRAINT #{table}_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id)"
    end

    for {table, column, parent} <- [
          {"workflow_versions", "workflow_id", "workflows"},
          {"tickets", "workflow_id", "workflows"},
          {"tickets", "workflow_version_id", "workflow_versions"},
          {"ticket_sections", "ticket_id", "tickets"},
          {"transition_events", "ticket_id", "tickets"},
          {"command_receipts", "ticket_id", "tickets"},
          {"outbox_messages", "ticket_id", "tickets"},
          {"outbox_messages", "event_id", "transition_events"},
          {"delivery_attempts", "outbox_message_id", "outbox_messages"}
        ] do
      execute "ALTER TABLE #{table} ADD CONSTRAINT #{table}_#{column}_tenant_fk FOREIGN KEY (#{column}, organization_id) REFERENCES #{parent}(id, organization_id)"
    end

    create unique_index(:transition_events, [:id, :ticket_id, :organization_id])

    execute "ALTER TABLE outbox_messages ADD CONSTRAINT outbox_event_ticket_tenant_fk FOREIGN KEY (event_id, ticket_id, organization_id) REFERENCES transition_events(id, ticket_id, organization_id)"

    execute """
    CREATE FUNCTION reject_organization_move() RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
    BEGIN IF NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN RAISE EXCEPTION 'organization ownership is immutable' USING ERRCODE = '23514'; END IF; RETURN NEW; END; $$
    """

    for table <- @tenant_tables,
        do:
          execute(
            "CREATE TRIGGER immutable_organization BEFORE UPDATE ON #{table} FOR EACH ROW EXECUTE FUNCTION reject_organization_move()"
          )

    execute """
    DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'instantflow_runtime') THEN
      CREATE ROLE instantflow_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
    END IF; END $$
    """

    execute "GRANT instantflow_runtime TO CURRENT_USER"
    execute "REVOKE CREATE ON SCHEMA public FROM PUBLIC"
    execute "GRANT USAGE ON SCHEMA public TO instantflow_runtime"

    for table <- ["organizations" | @tenant_tables] do
      field = if table == "organizations", do: "id", else: "organization_id"
      execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY"

      execute "CREATE POLICY tenant_isolation ON #{table} USING (#{field} = NULLIF(current_setting('instantflow.organization_id', true), '')::bigint) WITH CHECK (#{field} = NULLIF(current_setting('instantflow.organization_id', true), '')::bigint)"

      execute "GRANT SELECT, INSERT, UPDATE, DELETE ON #{table} TO instantflow_runtime"
    end

    execute "GRANT SELECT, INSERT, UPDATE, DELETE ON users, sessions TO instantflow_runtime"
    execute "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO instantflow_runtime"

    control_function(
      "organization_choices",
      "uid bigint",
      "TABLE(id bigint, slug text, name text, timezone text, status text)",
      "SELECT o.id, o.slug, o.name, o.timezone, o.status FROM public.organizations o JOIN public.memberships m ON m.organization_id=o.id JOIN public.users u ON u.id=m.user_id WHERE m.user_id=uid AND m.active AND u.active AND o.status='active' ORDER BY o.id"
    )

    control_function(
      "invitation_organization",
      "digest bytea",
      "bigint",
      "SELECT i.organization_id FROM public.invitations i JOIN public.organizations o ON o.id=i.organization_id WHERE i.token_hash=digest AND i.accepted_at IS NULL AND i.expires_at>now() AND o.status='active'"
    )

    control_function(
      "dispatch_organizations",
      "",
      "TABLE(id bigint)",
      "SELECT id FROM public.organizations WHERE status='active' ORDER BY id"
    )
  end

  defp control_function(name, args, returns, sql) do
    execute "CREATE FUNCTION #{name}(#{args}) RETURNS #{returns} LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$ #{sql} $$"

    signature =
      case name do
        "organization_choices" -> "bigint"
        "invitation_organization" -> "bytea"
        _ -> ""
      end

    execute "REVOKE ALL ON FUNCTION #{name}(#{signature}) FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION #{name}(#{signature}) TO instantflow_runtime"
  end

  def down do
    raise "Sprint 01A is forward-only. Stop application traffic and restore a coordinated backup into an isolated database; never delete another organization to roll back."
  end
end
