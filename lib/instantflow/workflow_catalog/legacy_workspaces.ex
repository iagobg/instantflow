defmodule Instantflow.WorkflowCatalog.LegacyWorkspaces do
  @moduledoc "Compatibility route discovery for phase-one domain adapters; never selects generated process pages."
  import Ecto.Query
  alias Instantflow.{Repo, Tenant}
  alias Instantflow.WorkflowCatalog.{Capabilities, Workspaces}

  # Compatibility endpoints for phase-one data only. Generated pages never dispatch through this adapter.
  def available?(scope, feature) do
    Tenant.read(
      scope,
      fn fresh ->
        versions = Workspaces.latest()

        case feature do
          :enrollment ->
            Enum.any?(versions, &(&1.definition["template_key"] == "enrollment"))

          :incident ->
            Enum.any?(versions, &(&1.definition["template_key"] == "incident"))

          :finance ->
            fresh.role != "parent" and
              (Enum.any?(versions, &Capabilities.enabled?(&1.definition, "finance")) or
                 (fresh.role == "admin" and
                    Repo.exists?(
                      from d in Instantflow.WorkflowCatalog.Draft,
                        where:
                          fragment(
                            "? @> ?",
                            d.definition,
                            type(^%{"capabilities" => ["finance"]}, :map)
                          )
                    )))
        end
      end,
      false
    )
  end
end
