defmodule Instantflow.Repo.Migrations.CreateIdentity do
  use Ecto.Migration

  def change do
    create table(:organizations) do
      add :name, :text, null: false
      add :timezone, :text, null: false, default: "America/Sao_Paulo"
      timestamps(type: :utc_datetime)
    end

    create constraint(:organizations, :single_organization, check: "id = 1")

    create table(:departments) do
      add :organization_id, references(:organizations), null: false
      add :name, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:departments, [:organization_id, :name])
    create unique_index(:departments, [:id, :organization_id])

    create table(:users) do
      add :name, :text, null: false
      add :email, :text, null: false
      add :password_hash, :text, null: false
      add :active, :boolean, null: false, default: true
      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
    create constraint(:users, :normalized_email, check: "email = lower(trim(email))")

    create table(:memberships) do
      add :user_id, references(:users), null: false
      add :organization_id, references(:organizations), null: false

      add :department_id, references(:departments, with: [organization_id: :organization_id]),
        null: false

      add :role, :text, null: false, default: "staff"
      add :active, :boolean, null: false, default: true
      timestamps(type: :utc_datetime)
    end

    create unique_index(:memberships, [:organization_id, :user_id])
    create constraint(:memberships, :valid_role, check: "role IN ('admin', 'staff')")

    create table(:invitations) do
      add :organization_id, references(:organizations), null: false

      add :department_id, references(:departments, with: [organization_id: :organization_id]),
        null: false

      add :invited_by_id, references(:users), null: false
      add :email, :text, null: false
      add :role, :text, null: false
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:invitations, [:token_hash])
    create constraint(:invitations, :valid_role, check: "role IN ('admin', 'staff')")

    create table(:sessions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:sessions, [:token_hash])
    create index(:sessions, [:user_id])
  end
end
