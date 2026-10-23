defmodule Instantflow.BuilderCompositionTest do
  use Instantflow.DataCase, async: true
  import Instantflow.IdentityFixtures
  alias Instantflow.{Finance, Operations, WorkflowCatalog, WorkflowRuntime}
  alias Instantflow.WorkflowCatalog.Templates
  alias Instantflow.WorkflowFixtures
  alias Instantflow.FinanceFixtures

  test "renamed operational lifecycle uses each visit's pinned definition across republication" do
    actor = staff_fixture()
    definition = Templates.starter("equipment_hire", "Locação", "item_service")

    definition =
      rename(definition, %{
        "open" => "in_use",
        "settled" => "returned",
        "settle" => "return_equipment"
      })

    bindings = %{
      "roles" => %{"operator" => ["admin"]},
      "departments" => %{"service_department" => actor.department_id}
    }

    assert {:ok, version} = WorkflowCatalog.publish(actor, definition, bindings)
    command = fn operation, attrs -> op(actor, version.workflow_id, operation, attrs) end
    assert {:ok, resource} = command.("add_resource", %{"name" => "Bancada"})

    visit_attrs = %{
      "resource_id" => resource["id"],
      "responsible_actor" => "Atendente",
      "business_date" => Date.to_iso8601(Operations.today(actor))
    }

    assert {:ok, first} = command.("open_session", visit_attrs)

    revised = rename(definition, %{"return_equipment" => "confirm_return"})
    assert {:ok, next} = WorkflowCatalog.publish(actor, revised, bindings, 1)

    assert {:ok, _} =
             command.("settle", %{
               "session_id" => first["id"],
               "expected_total" => 0,
               "payment_method" => "cash"
             })

    first_visit = Operations.visit(actor, first["id"], version.workflow_id)
    assert {:ok, first_record} = WorkflowRuntime.get(actor, first_visit.session.ticket_id)
    assert first_record.ticket.workflow_version_id == version.id
    assert first_record.ticket.stage == "returned"
    assert Enum.any?(first_record.events, &(&1.operation == "return_equipment"))

    assert {:ok, second} = command.("open_session", visit_attrs)

    assert {:ok, _} =
             command.("settle", %{
               "session_id" => second["id"],
               "expected_total" => 0,
               "payment_method" => "cash"
             })

    second_visit = Operations.visit(actor, second["id"], version.workflow_id)
    assert {:ok, second_record} = WorkflowRuntime.get(actor, second_visit.session.ticket_id)
    assert second_record.ticket.workflow_version_id == next.id
    assert Enum.any?(second_record.events, &(&1.operation == "confirm_return"))
  end

  test "finance reservations remain guarded when composed with resource sessions" do
    f = FinanceFixtures.finance_fixture()

    definition =
      f.version.definition
      |> Map.put("template_key", "equipment_purchase")
      |> Map.put("capabilities", ["operations", "finance", "core"])
      |> put_in(
        ["interface", "operations"],
        Instantflow.WorkflowCatalog.OperationalContract.defaults()
      )
      |> put_in(["interface", "lifecycle"], %{"close_transition" => "finish"})

    assert {:ok, version} = WorkflowCatalog.publish(f.admin, definition, f.version.bindings)

    assert {:ok, resource} =
             op(f.requester, version.workflow_id, "add_resource", %{"name" => "Compras"})

    assert {:ok, visit} =
             op(f.requester, version.workflow_id, "open_session", %{
               "resource_id" => resource["id"],
               "responsible_actor" => "Solicitante",
               "business_date" => Date.to_iso8601(Operations.today(f.requester))
             })

    session = Operations.visit(f.requester, visit["id"], version.workflow_id).session
    id = session.ticket_id

    assert {:ok, _} =
             FinanceFixtures.save(f.requester, id, "request", %{
               "summary" => "Equipamento",
               "justification" => "Reposição",
               "quantity" => 1,
               "amount" => 6000
             })

    assert {:ok, _} = WorkflowFixtures.transition(f.requester, id, "submit")
    assert {:ok, _} = WorkflowFixtures.transition(f.head, id, "academic_approve")
    assert {:error, :forbidden} = WorkflowFixtures.transition(f.requester, id, "reserve")
    assert {:ok, _} = WorkflowFixtures.transition(f.finance, id, "reserve")
    assert [%{reserved: 6000, available: 4000}] = Finance.accounts(f.finance)

    assert {:error, :forbidden} =
             op(f.requester, version.workflow_id, "settle", %{
               "session_id" => session.id,
               "expected_total" => 0,
               "payment_method" => "cash"
             })

    assert Operations.visit(f.requester, session.id, version.workflow_id).session.status == "open"
    assert [%{reserved: 6000, available: 4000}] = Finance.accounts(f.finance)
  end

  defp op(actor, workflow_id, operation, attrs) do
    Operations.command(
      actor,
      Map.merge(attrs, %{
        "operation" => operation,
        "workflow_id" => workflow_id,
        "key" => Ecto.UUID.generate()
      })
    )
  end

  defp rename(value, replacements) when is_map(value),
    do: Map.new(value, fn {k, v} -> {k, rename(v, replacements)} end)

  defp rename(value, replacements) when is_list(value),
    do: Enum.map(value, &rename(&1, replacements))

  defp rename(value, replacements), do: Map.get(replacements, value, value)
end
