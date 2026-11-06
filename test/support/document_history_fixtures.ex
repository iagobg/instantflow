defmodule Instantflow.DocumentHistoryFixtures do
  @moduledoc "Synthetic retained metadata for pagination and retention volume tests."
  import Instantflow.IdentityFixtures
  alias Instantflow.{BuilderFixtures, Participants, PrivateDocuments, Repo, WorkflowRuntime}
  alias Instantflow.Enrollment.Document

  def fixture(count) do
    admin = staff_fixture()
    clerk = staff_fixture("staff")
    visitor = staff_fixture("parent")
    definition = BuilderFixtures.document_definition()

    attachment =
      Enum.find(Enum.at(definition["sections"], 1)["fields"], &(&1["type"] == "attachment"))

    definition =
      update_in(definition, ["sections", Access.at(0), "fields"], &(&1 ++ [attachment]))

    version =
      BuilderFixtures.install(admin, definition, %{
        "roles" => %{"requester" => ["staff"], "reviewer" => ["admin"], "visitor" => ["parent"]},
        "departments" => %{"responsible" => admin.department_id}
      })

    {:ok, created} =
      WorkflowRuntime.command(clerk, %{
        "operation" => "create",
        "workflow_id" => version.workflow_id,
        "key" => Ecto.UUID.generate()
      })

    ticket_id = created["ticket_id"]

    for {operation, revision} <- [{"create", 0}, {"verify", 1}] do
      {:ok, _} =
        Participants.command(
          admin,
          BuilderFixtures.participant_command(ticket_id, visitor.id, operation, revision)
        )
    end

    {:ok, doc} =
      PrivateDocuments.upload(
        visitor,
        ticket_id,
        "customer_details",
        "evidence",
        "history.pdf",
        Instantflow.EnrollmentFixtures.pdf()
      )

    record = Repo.get!(Document, doc.id)
    record = Repo.update!(Ecto.Changeset.change(record, status: "deleted", content: <<>>))
    template = record |> Map.take(Document.__schema__(:fields)) |> Map.delete(:id)
    ids = [doc.id | insert(template, count - 1)] |> Enum.sort(:desc)

    %{
      admin: admin,
      clerk: clerk,
      visitor: visitor,
      version: version,
      ticket_id: ticket_id,
      template: template,
      ids: ids
    }
  end

  def insert(template, count) do
    rows =
      for _ <- List.duplicate(:row, count),
          do: Map.put(template, :object_key, Ecto.UUID.generate())

    rows
    |> Enum.chunk_every(500)
    |> Enum.flat_map(fn batch ->
      {_, records} = Repo.insert_all(Document, batch, returning: [:id])
      Enum.map(records, & &1.id)
    end)
  end
end
