defmodule Instantflow.WorkflowFixtures do
  import Instantflow.IdentityFixtures
  alias Instantflow.{WorkflowCatalog, WorkflowRuntime}

  def definition_fixture do
    definition =
      File.read!(Path.expand("../../design/examples/simple_approval.json", __DIR__))
      |> Jason.decode!()

    update_in(definition["transitions"], fn transitions ->
      Enum.map(transitions, fn t ->
        case t["key"] do
          "submit" ->
            Map.put(t, "actions", [
              %{"type" => "simulate_notification", "behavior" => "fail_once"}
            ])

          "approve" ->
            Map.put(t, "guard", %{"op" => "delivery_succeeded", "kind" => "simulate_notification"})

          _ ->
            t
        end
      end)
    end)
  end

  def workflow_fixture do
    admin = staff_fixture()
    requester = staff_fixture("staff")
    reviewer = staff_fixture("staff")
    definition = definition_fixture()

    bindings = %{
      "roles" => %{"requester" => ["admin", "staff"], "reviewer" => ["staff"]},
      "departments" => %{"review_department" => reviewer.department_id}
    }

    {:ok, version} = WorkflowCatalog.publish(admin, definition, bindings)

    %{
      admin: admin,
      requester: requester,
      reviewer: reviewer,
      version: version,
      definition: definition,
      bindings: bindings
    }
  end

  def create_ticket(fixture) do
    {:ok, result} =
      WorkflowRuntime.command(fixture.requester, %{
        "operation" => "create",
        "workflow_id" => fixture.version.workflow_id,
        "key" => key()
      })

    result["ticket_id"]
  end

  def save(actor, id, values, key \\ key()) do
    {:ok, data} = WorkflowRuntime.get(actor, id)
    section = Enum.find(data.sections, &(&1.key == "request"))

    WorkflowRuntime.command(actor, %{
      "operation" => "save_section",
      "key" => key,
      "ticket_id" => id,
      "section" => "request",
      "values" => values,
      "expected_stage_revision" => data.ticket.stage_revision,
      "expected_section_revision" => section.revision
    })
  end

  def transition_command(actor, id, edge, reason \\ nil) do
    {:ok, data} = WorkflowRuntime.get(actor, id)

    %{
      "operation" => "transition",
      "key" => key(),
      "ticket_id" => id,
      "transition" => edge,
      "expected_revision" => data.ticket.revision,
      "section_revisions" => Map.new(data.sections, &{&1.key, &1.revision}),
      "reason" => reason
    }
  end

  def transition(actor, id, edge, reason \\ nil),
    do: WorkflowRuntime.command(actor, transition_command(actor, id, edge, reason))

  def key, do: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

  def values,
    do: %{
      "summary" => "Material para atividade",
      "justification" => "Atividade pedagógica fictícia."
    }
end
