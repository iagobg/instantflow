defmodule Instantflow.Repo.Migrations.IndexWorkspaceHistoryClassification do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:workflow_versions, [:organization_id, :workflow_id],
                           name: :workflow_versions_staff_history_index,
                           where:
                             "jsonb_exists(definition, 'communications') OR jsonb_path_exists(definition, '$.interface.pages[*].participant')"
                         )
  end
end
