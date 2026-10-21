defmodule Instantflow.IncidentFixtures do
  import Instantflow.IdentityFixtures
  alias Instantflow.{Access, Identity, Incidents, WorkflowRuntime}
  alias Instantflow.WorkflowFixtures, as: W

  def incident_fixture do
    admin = staff_fixture()

    actors =
      for {name, role} <- [
            teacher: "teacher",
            dean: "dean",
            counselor: "counselor",
            other_counselor: "counselor"
          ],
          into: %{} do
        member = staff_fixture("staff")
        {:ok, _} = Access.grant(admin, member.id, member.department_id, role)
        {name, Identity.scope(member.user_id, member.organization_id)}
      end

    deps = %{
      "dean_department" => admin.department_id,
      "support_department" => admin.department_id
    }

    {:ok, version} = Incidents.install(admin, deps)
    Map.merge(actors, %{admin: admin, version: version, departments: deps})
  end

  def report(f) do
    {:ok, result} =
      WorkflowRuntime.command(f.teacher, %{
        "operation" => "create",
        "workflow_id" => f.version.workflow_id,
        "key" => W.key()
      })

    id = result["ticket_id"]

    {:ok, _} =
      Instantflow.FinanceFixtures.save(f.teacher, id, "report", %{
        "facts" => "Relato sintético",
        "students" => "Estudante fictício",
        "occurred_at" => "2026-10-21T12:00:00Z",
        "location" => "Pátio fictício",
        "urgency" => "Urgente"
      })

    {:ok, _} = W.transition(f.teacher, id, "submit")
    id
  end

  def assign(actor, id, member_id, reason) do
    {:ok, data} = WorkflowRuntime.get(actor, id)

    WorkflowRuntime.command(
      actor,
      assignment_command(id, data.ticket.revision, member_id, reason)
    )
  end

  def assignment_command(id, revision, member_id, reason) do
    %{
      "operation" => "assign",
      "key" => W.key(),
      "ticket_id" => id,
      "section" => "support",
      "membership_id" => member_id,
      "expected_revision" => revision,
      "reason" => reason
    }
  end

  def followup(f, id) do
    {:ok, _} = assign(f.dean, id, f.counselor.id, "Acompanhamento fictício")

    {:ok, _} =
      Instantflow.FinanceFixtures.save(f.dean, id, "discipline", %{
        "triage" => "Avaliação fictícia"
      })

    {:ok, _} = W.transition(f.dean, id, "triage")
  end
end
