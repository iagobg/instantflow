defmodule Instantflow.FinanceFixtures do
  import Instantflow.IdentityFixtures
  alias Instantflow.{Access, Finance, Identity, WorkflowRuntime}
  alias Instantflow.WorkflowFixtures

  def finance_fixture(template \\ "requisition") do
    admin = staff_fixture()

    actors =
      for {key, roles} <- [
            requester: ["teacher"],
            head: ["head"],
            finance: ["finance", "finance_allocator"],
            operations: ["operations"],
            safety: ["dean"],
            reverser: ["finance_reverser"]
          ],
          into: %{} do
        actor = staff_fixture("staff")
        for role <- roles, do: Access.grant(admin, actor.id, actor.department_id, role)
        {key, Identity.scope(actor.user_id, actor.organization_id)}
      end

    finance = actors.finance

    {:ok, account} =
      Finance.create_account(admin, finance.department_id, "Orçamento compartilhado")

    {:ok, _} =
      Finance.allocate(finance, account.id, 10_000, "Dotação fictícia", WorkflowFixtures.key())

    departments =
      Map.new(~w(head finance operations safety), &{&1 <> "_department", finance.department_id})

    {:ok, version} = Finance.install(admin, template, departments, account.id)

    Map.merge(actors, %{
      admin: admin,
      account: account,
      version: version,
      departments: departments
    })
  end

  def request(f, amount \\ 6000) do
    {:ok, result} =
      WorkflowRuntime.command(f.requester, %{
        "operation" => "create",
        "workflow_id" => f.version.workflow_id,
        "key" => WorkflowFixtures.key()
      })

    id = result["ticket_id"]

    values = %{
      "summary" => "Atividade fictícia",
      "justification" => "Demonstração",
      "quantity" => 4,
      "amount" => amount
    }

    values =
      if f.version.definition["template_key"] == "field_trip",
        do:
          Map.merge(
            values,
            %{
              "date" => "2026-11-12",
              "destination" => "Museu fictício",
              "itinerary" => "Saída às 09h",
              "risks" => "Acompanhamento por docentes"
            }
          ),
        else: values

    {:ok, _} = save(f.requester, id, "request", values)
    {:ok, _} = WorkflowFixtures.transition(f.requester, id, "submit")
    {:ok, _} = WorkflowFixtures.transition(f.head, id, "academic_approve")
    id
  end

  def save(actor, id, section_key, values) do
    {:ok, data} = WorkflowRuntime.get(actor, id)
    section = Enum.find(data.sections, &(&1.key == section_key))

    WorkflowRuntime.command(actor, %{
      "operation" => "save_section",
      "key" => WorkflowFixtures.key(),
      "ticket_id" => id,
      "section" => section_key,
      "values" => values,
      "expected_stage_revision" => data.ticket.stage_revision,
      "expected_section_revision" => section.revision
    })
  end
end
