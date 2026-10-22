defmodule Instantflow.WorkflowRuntime.LegacyResets do
  @moduledoc "Pinned pre-Sprint-10 finance reset compatibility. New publication requires explicit targets."
  alias Instantflow.Repo

  def apply!(version, sections, edge) do
    initial = Enum.find(version.definition["stages"], & &1["initial"])["key"]

    if edge["finance"] && edge["finance"]["operation"] == "release" && edge["to"] == initial do
      for section <- sections,
          definition = Enum.find(version.definition["sections"], &(&1["key"] == section.key)),
          not Enum.any?(definition["fields"], &(&1["type"] == "money")) do
        section
        |> Ecto.Changeset.change(values: %{}, revision: section.revision + 1)
        |> Repo.update!()
      end
    end

    %{}
  end
end
