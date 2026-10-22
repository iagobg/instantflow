defmodule Instantflow.Repo.Migrations.ScopeOperationalRecordsToWorkflows do
  use Ecto.Migration

  @tables ~w(catalog_products service_resources service_sessions fulfillment_batches fulfillment_lines operation_receipts operation_day_closes)
  @backfill_definition ~S"""
  {
  "format_version": "1.0",
  "template_key": "resource_service",
  "template_version": "0.1.0",
  "locale": "pt-BR",
  "name": "Atendimento com itens",
  "description": "Atendimentos por recurso, itens de catálogo e lotes por destino. Use o espaço operacional para abrir e fechar.",
  "capabilities": [
    "core",
    "operations"
  ],
  "role_requirements": [
    {
      "key": "operator",
      "label": "Operador"
    }
  ],
  "sections": [
    {
      "key": "service",
      "label": "Atendimento",
      "classification": "internal",
      "access": [
        {
          "role": "operator",
          "scope": "requester",
          "read": true,
          "edit_stages": []
        },
        {
          "role": "operator",
          "scope": "assigned_department",
          "read": true,
          "edit_stages": []
        }
      ],
      "fields": [
        {
          "key": "reference",
          "label": "Referência operacional",
          "type": "short_text"
        }
      ]
    }
  ],
  "stages": [
    {
      "key": "open",
      "label": "Em atendimento",
      "initial": true,
      "terminal": false
    },
    {
      "key": "settled",
      "label": "Encerrado",
      "initial": false,
      "terminal": true
    }
  ],
  "creation": {
    "roles": [
      "operator"
    ]
  },
  "transitions": [
    {
      "key": "settle",
      "label": "Encerrar pelo espaço operacional",
      "from": "open",
      "to": "settled",
      "actors": [
        {
          "role": "operator",
          "scope": "requester"
        },
        {
          "role": "operator",
          "scope": "assigned_department"
        }
      ],
      "required_fields": [],
      "require_reason": false,
      "kind": "forward",
      "actions": []
    }
  ],
  "bindings": [
    {
      "key": "service_department",
      "type": "department",
      "label": "Departamento operacional"
    }
  ],
  "assignment": {
    "department_binding": "service_department"
  },
  "views": [
    {
      "key": "services",
      "label": "Atendimentos",
      "type": "table",
      "columns": [
        "stage"
      ]
    }
  ],
  "interface": {
    "pages": [
      {
        "key": "overview",
        "label": "Atendimento",
        "blocks": [
          "catalog",
          "resources",
          "items",
          "batches",
          "settlement",
          "daily_summary"
        ]
      }
    ],
    "labels": {
      "resource": "Mesa",
      "resources": "Mesas",
      "catalog": "Cardápio",
      "actor": "Garçom",
      "destination": "Destino de preparo"
    },
    "lifecycle": {
      "close_transition": "settle"
    }
  }
  }
  """

  def up do
    # Preserve pre-session menus too: the initial implementation created the workflow lazily.
    execute """
    INSERT INTO workflows(organization_id,key,name,inserted_at,updated_at)
    SELECT DISTINCT o.id,'resource_service','Atendimento com itens',now(),now() FROM organizations o
    WHERE EXISTS (SELECT 1 FROM catalog_products p WHERE p.organization_id=o.id)
       OR EXISTS (SELECT 1 FROM service_resources r WHERE r.organization_id=o.id)
       OR EXISTS (SELECT 1 FROM operation_receipts r WHERE r.organization_id=o.id)
    ON CONFLICT (organization_id,key) DO NOTHING
    """

    definition =
      @backfill_definition |> String.replace("'", "''")

    execute """
    INSERT INTO workflow_versions(organization_id,workflow_id,number,definition,bindings,published_by_id,inserted_at,updated_at)
    SELECT w.organization_id,w.id,1,'#{definition}'::jsonb,
      jsonb_build_object('roles',jsonb_build_object('operator',jsonb_build_array('admin')),
        'departments',jsonb_build_object('service_department',m.department_id)),m.user_id,now(),now()
    FROM workflows w JOIN LATERAL (SELECT user_id,department_id FROM memberships WHERE organization_id=w.organization_id ORDER BY (role='admin') DESC,id LIMIT 1) m ON true
    WHERE w.key='resource_service' AND NOT EXISTS (SELECT 1 FROM workflow_versions v WHERE v.workflow_id=w.id)
    """

    for table <- @tables do
      alter table(String.to_atom(table)), do: add(:workflow_id, :bigint)

      if table in ~w(fulfillment_lines operation_receipts operation_day_closes),
        do: execute("ALTER TABLE #{table} DISABLE TRIGGER immutable_operation_record")

      execute "UPDATE #{table} t SET workflow_id=w.id FROM workflows w WHERE w.organization_id=t.organization_id AND w.key='resource_service'"

      if table in ~w(fulfillment_lines operation_receipts operation_day_closes),
        do: execute("ALTER TABLE #{table} ENABLE TRIGGER immutable_operation_record")

      execute "ALTER TABLE #{table} ALTER COLUMN workflow_id SET NOT NULL"

      execute "ALTER TABLE #{table} ADD CONSTRAINT #{table}_workflow_tenant FOREIGN KEY (workflow_id,organization_id) REFERENCES workflows(id,organization_id)"

      create unique_index(String.to_atom(table), [:id, :organization_id, :workflow_id])
    end

    # Add presentation through a new immutable version; never rewrite an old publication or pinned request.
    execute """
    INSERT INTO workflow_versions(organization_id,workflow_id,number,definition,bindings,published_by_id,inserted_at,updated_at)
    SELECT v.organization_id,v.workflow_id,v.number+1,
      jsonb_set(jsonb_set(v.definition,'{capabilities}',(v.definition->'capabilities') || '["operations"]'::jsonb),'{interface}','{"pages": [{"key": "overview", "label": "Atendimento", "blocks": ["catalog", "resources", "items", "batches", "settlement", "daily_summary"]}], "labels": {"resource": "Mesa", "resources": "Mesas", "catalog": "Cardápio", "actor": "Garçom", "destination": "Destino de preparo"}, "lifecycle": {"close_transition": "settle"}}'::jsonb),
      v.bindings,v.published_by_id,now(),now()
    FROM workflow_versions v
    WHERE (EXISTS (SELECT 1 FROM catalog_products p WHERE p.workflow_id=v.workflow_id) OR EXISTS (SELECT 1 FROM service_resources r WHERE r.workflow_id=v.workflow_id) OR EXISTS (SELECT 1 FROM service_sessions s WHERE s.workflow_id=v.workflow_id))
      AND v.number=(SELECT max(v2.number) FROM workflow_versions v2 WHERE v2.workflow_id=v.workflow_id)
      AND NOT ((v.definition->'capabilities') @> '["operations"]'::jsonb)
    """

    drop unique_index(:catalog_products, [:organization_id, :name])
    create unique_index(:catalog_products, [:organization_id, :workflow_id, :name])
    drop unique_index(:service_resources, [:organization_id, :name])
    create unique_index(:service_resources, [:organization_id, :workflow_id, :name])
    drop unique_index(:operation_day_closes, [:organization_id, :business_date])
    create unique_index(:operation_day_closes, [:organization_id, :workflow_id, :business_date])
    drop unique_index(:operation_receipts, [:organization_id, :actor_id, :key])
    create unique_index(:operation_receipts, [:organization_id, :workflow_id, :actor_id, :key])
    create unique_index(:tickets, [:id, :organization_id, :workflow_id])

    for {table, column, target} <- [
          {"service_sessions", "resource_id", "service_resources"},
          {"service_sessions", "ticket_id", "tickets"},
          {"fulfillment_batches", "session_id", "service_sessions"},
          {"fulfillment_batches", "source_id", "fulfillment_batches"},
          {"fulfillment_lines", "batch_id", "fulfillment_batches"},
          {"fulfillment_lines", "product_id", "catalog_products"}
        ] do
      execute "ALTER TABLE #{table} ADD CONSTRAINT #{table}_#{column}_process FOREIGN KEY (#{column},organization_id,workflow_id) REFERENCES #{target}(id,organization_id,workflow_id)"
    end

    execute """
    CREATE FUNCTION reject_workflow_move() RETURNS trigger LANGUAGE plpgsql AS $body$
    BEGIN
      IF NEW.workflow_id IS DISTINCT FROM OLD.workflow_id THEN RAISE EXCEPTION 'Process ownership is immutable'; END IF;
      RETURN NEW;
    END $body$
    """

    for table <- @tables do
      execute "CREATE TRIGGER immutable_workflow BEFORE UPDATE ON #{table} FOR EACH ROW EXECUTE FUNCTION reject_workflow_move()"
    end
  end

  def down, do: raise("Process isolation is forward-only; restore a coordinated backup.")
end
