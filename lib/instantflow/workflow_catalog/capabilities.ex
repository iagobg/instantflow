defmodule Instantflow.WorkflowCatalog.Capabilities do
  @moduledoc "Closed, additive capability contract shared by authoring and runtime."

  @supported ~w(core finance operations documents participants)

  def supported, do: @supported

  @doc "Versioned ownership and execution metadata for the closed capability set."
  def descriptors do
    [
      %{
        id: "core",
        version: 1,
        owner: Instantflow.WorkflowRuntime,
        tables: ~w(tickets ticket_sections transition_events command_receipts outbox_messages),
        dependencies: [],
        conflicts: [],
        bindings: ~w(roles departments),
        declarations: ~w(sections stages creation transitions assignment),
        guards: ~w(required_fields guard),
        effects: ~w(section_values stage audit receipt outbox),
        projections: ~w(records history),
        migration: :immutable_versions
      },
      %{
        id: "finance",
        version: 1,
        owner: Instantflow.Finance,
        tables: ~w(budget_accounts budget_holds budget_entries),
        dependencies: ["core"],
        conflicts: [],
        bindings: ["budgets"],
        declarations: ["transitions.finance", "transitions.reset", "interface.finance"],
        guards: ~w(balance authority receipt_quantities),
        effects: ~w(reserve release post reverse complete),
        projections: ~w(accounts reservations process_summary shared_account_summary),
        migration: :immutable_versions
      },
      %{
        id: "operations",
        version: 1,
        owner: Instantflow.Operations,
        tables:
          ~w(catalog_products service_resources service_sessions fulfillment_lines fulfillment_batches operation_receipts operation_day_closes),
        dependencies: ["core"],
        conflicts: [],
        bindings: [],
        declarations: ~w(interface.lifecycle interface.pages),
        guards: ~w(open_session settlement),
        effects: ~w(catalog resource session item settlement),
        projections: ~w(catalog resources sessions daily_summary),
        migration: :immutable_versions
      },
      %{
        id: "documents",
        version: 1,
        owner: Instantflow.PrivateDocuments,
        tables: ~w(private_documents),
        dependencies: ["core"],
        conflicts: [],
        bindings: [],
        declarations: ["sections.fields.document_policy"],
        guards: ~w(section_access reviewer quarantine integrity),
        effects: ~w(upload release reject delete),
        projections: ~w(private_metadata),
        migration: :immutable_versions
      },
      %{
        id: "participants",
        version: 1,
        owner: Instantflow.Participants,
        tables: ~w(ticket_participants),
        dependencies: ["core"],
        conflicts: [],
        bindings: [],
        declarations: ["participants"],
        guards: ~w(verified_relationship declared_manager revision),
        effects: ~w(create verify revoke),
        projections: ~w(relationship_access),
        migration: :immutable_versions
      }
    ]
  end

  def descriptor(id), do: Enum.find(descriptors(), &(&1.id == id))

  def enabled?(definition, capability),
    do: capability in @supported and capability in Map.get(definition, "capabilities", [])

  def valid?(capabilities) when is_list(capabilities),
    do:
      "core" in capabilities and Enum.uniq(capabilities) == capabilities and
        Enum.all?(capabilities, &(&1 in @supported))

  def valid?(_), do: false
end
