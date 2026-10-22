defmodule Instantflow.CuratedFixtures do
  import Instantflow.IdentityFixtures
  alias Instantflow.{BuilderFixtures, FinanceFixtures, Participants, WorkflowRuntime}

  def definition(behavior \\ "fail_once") do
    BuilderFixtures.participant_definition("independent_release")
    |> Map.update!("capabilities", &(&1 ++ ["communications"]))
    |> Map.put("communications", [
      %{
        "key" => "outcome",
        "label" => "Resultado compartilhado",
        "recipient_relationship" => "claimant",
        "fields" => ["request.summary"],
        "behavior" => behavior,
        "release_actors" => [
          %{
            "role" => "reviewer",
            "scope" => "workflow_department",
            "department_binding" => "responsible"
          }
        ]
      }
    ])
    # The recipient relationship is eligible but confers no record access.
    |> Map.update!("sections", &Enum.reject(&1, fn s -> s["key"] == "customer_details" end))
    |> update_in(
      ["transitions", Access.at(0)],
      &Map.put(&1, "guard", %{"op" => "communication_succeeded", "communication" => "outcome"})
    )
  end

  def fixture(behavior \\ "fail_once") do
    admin = staff_fixture()
    clerk = staff_fixture("staff")

    recipient =
      BuilderFixtures.invite_external(admin, "curated-#{Ecto.UUID.generate()}@example.test")

    other = BuilderFixtures.invite_external(admin, "curated-#{Ecto.UUID.generate()}@example.test")

    bindings = %{
      "roles" => %{"requester" => ["staff"], "reviewer" => ["admin"], "visitor" => ["external"]},
      "departments" => %{"responsible" => admin.department_id}
    }

    version = BuilderFixtures.install(admin, definition(behavior), bindings)

    {:ok, created} =
      WorkflowRuntime.command(clerk, %{
        "operation" => "create",
        "workflow_id" => version.workflow_id,
        "key" => Ecto.UUID.generate()
      })

    id = created["ticket_id"]
    {:ok, _} = FinanceFixtures.save(clerk, id, "request", %{"summary" => "RELEASED-ORIGINAL"})

    for {op, rev} <- [{"create", 0}, {"verify", 1}] do
      {:ok, _} =
        Participants.command(
          admin,
          BuilderFixtures.participant_command(id, recipient.id, op, rev)
        )
    end

    %{
      admin: admin,
      clerk: clerk,
      recipient: recipient,
      other: other,
      version: version,
      id: id,
      bindings: bindings
    }
  end

  def release(f, key \\ Ecto.UUID.generate()) do
    {:ok, data} = WorkflowRuntime.get(f.admin, f.id)

    Instantflow.Delivery.Curated.release(
      f.admin,
      f.id,
      "outcome",
      f.recipient.id,
      data.ticket.revision,
      key
    )
  end
end
