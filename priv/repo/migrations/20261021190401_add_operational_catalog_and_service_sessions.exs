defmodule Instantflow.Repo.Migrations.AddOperationalCatalogAndServiceSessions do
  use Ecto.Migration

  def up do
    create table(:catalog_products) do
      add :organization_id, references(:organizations), null: false
      add :name, :text, null: false
      add :category, :text, null: false
      add :price, :bigint, null: false
      add :destination, :text, null: false
      add :active, :boolean, null: false, default: true
      add :revision, :integer, null: false, default: 1
    end

    create unique_index(:catalog_products, [:organization_id, :name])

    create constraint(:catalog_products, :product_values,
             check:
               "price >= 0 AND price <= 100000000 AND length(name) BETWEEN 1 AND 120 AND length(category) BETWEEN 1 AND 80 AND length(destination) BETWEEN 1 AND 80 AND revision > 0"
           )

    create table(:service_resources) do
      add :organization_id, references(:organizations), null: false
      add :name, :text, null: false
    end

    create unique_index(:service_resources, [:organization_id, :name])
    create constraint(:service_resources, :resource_name, check: "length(name) BETWEEN 1 AND 80")

    create table(:service_sessions) do
      add :organization_id, references(:organizations), null: false
      add :resource_id, :bigint, null: false
      add :ticket_id, :bigint, null: false
      add :resource_name, :text, null: false
      add :waiter, :text, null: false
      add :business_date, :date, null: false
      add :status, :text, null: false, default: "open"
      add :total, :bigint, null: false, default: 0
      add :payment_method, :text
      add :opened_at, :utc_datetime, null: false
      add :settled_at, :utc_datetime
    end

    create unique_index(:service_sessions, [:ticket_id])

    create unique_index(:service_sessions, [:resource_id],
             where: "status = 'open'",
             name: :one_open_session_per_resource
           )

    create constraint(:service_sessions, :session_state,
             check:
               "length(waiter) BETWEEN 1 AND 120 AND total >= 0 AND ((status = 'open' AND settled_at IS NULL AND payment_method IS NULL) OR (status = 'settled' AND settled_at IS NOT NULL AND payment_method IN ('cash','card','pix')))"
           )

    create table(:fulfillment_batches) do
      add :organization_id, references(:organizations), null: false
      add :session_id, :bigint, null: false
      add :destination, :text, null: false
      add :kind, :text, null: false, default: "order"
      add :source_id, :bigint
      add :status, :text, null: false, default: "pending"
      add :waiter, :text, null: false
      add :reason, :text
      add :print_count, :integer, null: false, default: 0
      add :inserted_at, :utc_datetime, null: false
    end

    create unique_index(:fulfillment_batches, [:source_id], where: "source_id IS NOT NULL")

    create constraint(:fulfillment_batches, :batch_state,
             check:
               "status IN ('pending','handed','cancelled') AND print_count >= 0 AND ((kind = 'order' AND source_id IS NULL) OR (kind = 'cancellation' AND source_id IS NOT NULL AND length(reason) BETWEEN 1 AND 500))"
           )

    create table(:fulfillment_lines) do
      add :organization_id, references(:organizations), null: false
      add :batch_id, :bigint, null: false
      add :product_id, :bigint, null: false
      add :name, :text, null: false
      add :unit_price, :bigint, null: false
      add :quantity, :integer, null: false
      add :notes, :text, null: false, default: ""
    end

    create constraint(:fulfillment_lines, :line_values,
             check:
               "quantity BETWEEN 1 AND 999 AND unit_price BETWEEN 0 AND 100000000 AND length(notes) <= 300"
           )

    create table(:operation_receipts) do
      add :organization_id, references(:organizations), null: false
      add :actor_id, references(:users), null: false
      add :key, :text, null: false
      add :operation, :text, null: false
      add :digest, :binary, null: false
      add :result, :map, null: false
      add :reason, :text
      add :inserted_at, :utc_datetime, null: false
    end

    create unique_index(:operation_receipts, [:organization_id, :actor_id, :key])

    create table(:operation_day_closes) do
      add :organization_id, references(:organizations), null: false
      add :business_date, :date, null: false
      add :actor_id, references(:users), null: false
      add :summary, :map, null: false
      add :inserted_at, :utc_datetime, null: false
    end

    create unique_index(:operation_day_closes, [:organization_id, :business_date])

    for table <-
          ~w(catalog_products service_resources service_sessions fulfillment_batches fulfillment_lines operation_receipts operation_day_closes) do
      create unique_index(String.to_atom(table), [:id, :organization_id])
      execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY"

      execute "CREATE POLICY tenant_isolation ON #{table} USING (organization_id = NULLIF(current_setting('instantflow.organization_id', true), '')::bigint) WITH CHECK (organization_id = NULLIF(current_setting('instantflow.organization_id', true), '')::bigint)"

      execute "CREATE TRIGGER immutable_organization BEFORE UPDATE ON #{table} FOR EACH ROW EXECUTE FUNCTION reject_organization_move()"

      execute "GRANT SELECT, INSERT, UPDATE ON #{table} TO instantflow_runtime"
      execute "GRANT USAGE, SELECT ON SEQUENCE #{table}_id_seq TO instantflow_runtime"
    end

    for {table, column, target} <- [
          {"service_sessions", "resource_id", "service_resources"},
          {"service_sessions", "ticket_id", "tickets"},
          {"fulfillment_batches", "session_id", "service_sessions"},
          {"fulfillment_batches", "source_id", "fulfillment_batches"},
          {"fulfillment_lines", "batch_id", "fulfillment_batches"},
          {"fulfillment_lines", "product_id", "catalog_products"}
        ] do
      execute "ALTER TABLE #{table} ADD CONSTRAINT #{table}_#{column}_tenant FOREIGN KEY (#{column}, organization_id) REFERENCES #{target}(id, organization_id)"
    end

    for table <- ~w(fulfillment_lines operation_receipts operation_day_closes) do
      execute "CREATE TRIGGER immutable_operation_record BEFORE UPDATE OR DELETE ON #{table} FOR EACH ROW EXECUTE FUNCTION reject_immutable_change()"
    end
  end

  def down, do: raise("Operational history is forward-only; restore a coordinated backup.")
end
