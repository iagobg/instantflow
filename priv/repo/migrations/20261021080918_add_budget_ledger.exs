defmodule Instantflow.Repo.Migrations.AddBudgetLedger do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE membership_grants DROP CONSTRAINT registered_role"

    execute "ALTER TABLE membership_grants ADD CONSTRAINT registered_role CHECK (role IN ('teacher','admissions','head','finance','finance_allocator','finance_reverser','operations','it','dean','counselor'))"

    create table(:budget_accounts) do
      add :organization_id, references(:organizations), null: false
      add :department_id, :bigint, null: false
      add :name, :text, null: false
      add :allocated, :bigint, null: false, default: 0
      add :reserved, :bigint, null: false, default: 0
      add :spent, :bigint, null: false, default: 0
    end

    create unique_index(:budget_accounts, [:id, :organization_id])
    create unique_index(:budget_accounts, [:organization_id, :department_id, :name])

    execute "ALTER TABLE budget_accounts ADD CONSTRAINT budget_department_tenant FOREIGN KEY (department_id, organization_id) REFERENCES departments(id, organization_id)"

    create constraint(:budget_accounts, :budget_totals,
             check:
               "allocated >= 0 AND reserved >= 0 AND spent >= 0 AND allocated >= reserved + spent"
           )

    create table(:budget_holds) do
      add :organization_id, references(:organizations), null: false
      add :account_id, :bigint, null: false
      add :ticket_id, :bigint, null: false
      add :amount, :bigint, null: false
      add :status, :text, null: false
    end

    create unique_index(:budget_holds, [:ticket_id])

    create constraint(:budget_holds, :hold_values,
             check: "amount > 0 AND status IN ('reserved','posted','released','reversed')"
           )

    create table(:budget_entries) do
      add :organization_id, references(:organizations), null: false
      add :account_id, :bigint, null: false
      add :ticket_id, :bigint
      add :actor_id, references(:users), null: false
      add :operation, :text, null: false
      add :amount, :bigint, null: false
      add :reason, :text, null: false
      add :key, :text, null: false
      add :inserted_at, :utc_datetime, null: false
    end

    create unique_index(:budget_entries, [:organization_id, :key])

    for table <- ~w(budget_holds budget_entries) do
      execute "ALTER TABLE #{table} ADD CONSTRAINT #{table}_account_tenant FOREIGN KEY (account_id, organization_id) REFERENCES budget_accounts(id, organization_id)"

      execute "ALTER TABLE #{table} ADD CONSTRAINT #{table}_ticket_tenant FOREIGN KEY (ticket_id, organization_id) REFERENCES tickets(id, organization_id)"
    end

    for table <- ~w(budget_accounts budget_holds budget_entries) do
      execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY"

      execute "CREATE POLICY tenant_isolation ON #{table} USING (organization_id = NULLIF(current_setting('instantflow.organization_id', true), '')::bigint) WITH CHECK (organization_id = NULLIF(current_setting('instantflow.organization_id', true), '')::bigint)"

      execute "CREATE TRIGGER immutable_organization BEFORE UPDATE ON #{table} FOR EACH ROW EXECUTE FUNCTION reject_organization_move()"

      execute "GRANT SELECT, INSERT, UPDATE, DELETE ON #{table} TO instantflow_runtime"
      execute "GRANT USAGE, SELECT ON SEQUENCE #{table}_id_seq TO instantflow_runtime"
    end

    execute "CREATE TRIGGER immutable_budget_entry BEFORE UPDATE OR DELETE ON budget_entries FOR EACH ROW EXECUTE FUNCTION reject_immutable_change()"
  end

  def down, do: raise("Finance history is forward-only; restore a coordinated backup.")
end
