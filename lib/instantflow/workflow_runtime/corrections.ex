defmodule Instantflow.WorkflowRuntime.Corrections do
  @moduledoc "Atomic explicit section invalidation within the coordinator's existing transaction."
  alias Instantflow.Repo

  def apply!(_version, sections, edge) do
    case edge["reset"] do
      nil ->
        %{}

      spec ->
        for section <- sections,
            section.key in (spec["sections"] ++ spec["invalidate_approvals"]) do
          section
          |> Ecto.Changeset.change(values: %{}, revision: section.revision + 1)
          |> Repo.update!()
        end

        %{
          "reset_sections" => spec["sections"],
          "invalidated_approvals" => spec["invalidate_approvals"]
        }
    end
  end
end
