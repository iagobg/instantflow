defmodule Instantflow.Repo.Migrations.IndexOperationalReadJoins do
  use Ecto.Migration

  def change do
    create index(:service_sessions, [:organization_id, :workflow_id, :business_date, :status])
    create index(:fulfillment_batches, [:organization_id, :session_id, :id])
    create index(:fulfillment_lines, [:organization_id, :batch_id, :id])
    create index(:catalog_products, [:organization_id, :workflow_id, :category, :name, :id])
  end
end
