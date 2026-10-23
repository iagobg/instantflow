defmodule Instantflow.OperationsTest do
  use Instantflow.DataCase, async: true
  import Instantflow.OperationsFixtures
  import Instantflow.IdentityFixtures
  alias Instantflow.{Operations, Repo, Tenant, WorkflowRuntime}
  alias Instantflow.Operations.{Product, Line, Receipt, Session}

  test "menu selection creates destination batches with immutable prices, waiter and retry receipts" do
    f = operations_fixture()
    visit = open_visit(f)

    command = %{
      "operation" => "submit_batch",
      "key" => Ecto.UUID.generate(),
      "session_id" => visit,
      "responsible_actor" => "Ana",
      "lines" => [item(f.actor, f.soup, 2), item(f.actor, f.asado)]
    }

    assert {:ok, result} = Operations.command(f.actor, command)
    assert {:ok, ^result} = Operations.command(f.actor, command)
    data = Operations.visit(f.actor, visit)
    assert data.total == 13100
    assert Enum.map(data.batches, & &1.destination) == ["Cozinha", "Parrilla"]
    assert Enum.all?(data.batches, &(&1.waiter == "Ana"))
    assert Enum.sum(Enum.map(data.batches, &length(&1.lines))) == 2
    product = Repo.get!(Product, f.soup)

    assert {:ok, _} =
             operation(f.actor, "save_product", %{
               "id" => product.id,
               "revision" => product.revision,
               "name" => "Sopa nova",
               "category" => product.category,
               "price" => 9900,
               "destination" => "Parrilla"
             })

    assert Operations.visit(f.actor, visit).total == 13100
    assert hd(hd(Operations.visit(f.actor, visit).batches).lines).name == "Sopa"

    assert {:error, :catalog_changed} =
             operation(f.actor, "submit_batch", Map.drop(command, ["key", "operation"]))

    assert {:error, :idempotency_mismatch} =
             Operations.command(f.actor, Map.put(command, "responsible_actor", "Outra pessoa"))
  end

  test "handoff gates checkout, reprinting is separate, table reuse preserves the old visit and daily total" do
    f = operations_fixture()
    visit = open_visit(f)

    assert {:error, :occupied} =
             operation(f.actor, "open_session", %{
               "resource_id" => f.resource,
               "responsible_actor" => "Carlos",
               "business_date" => Date.to_iso8601(Operations.today(f.actor))
             })

    assert {:ok, %{"ids" => [batch]}} =
             operation(f.actor, "submit_batch", %{
               "session_id" => visit,
               "lines" => [item(f.actor, f.soup, 2)]
             })

    checkout = %{"session_id" => visit, "expected_total" => 5100, "payment_method" => "pix"}
    assert {:error, :pending_handoff} = operation(f.actor, "settle", checkout)
    assert {:ok, %{"copy" => 1}} = operation(f.actor, "print_ticket", %{"batch_id" => batch})
    assert {:ok, %{"copy" => 2}} = operation(f.actor, "print_ticket", %{"batch_id" => batch})
    assert {:error, :pending_handoff} = operation(f.actor, "settle", checkout)
    assert {:ok, _} = operation(f.actor, "handoff", %{"batch_id" => batch})

    assert {:error, :conflict} =
             operation(f.actor, "settle", Map.put(checkout, "expected_total", 5000))

    cmd = Map.merge(checkout, %{"operation" => "settle", "key" => Ecto.UUID.generate()})
    assert {:ok, result} = Operations.command(f.actor, cmd)
    assert {:ok, ^result} = Operations.command(f.actor, cmd)

    assert {:ok, %{ticket: %{stage: "settled"}}} =
             WorkflowRuntime.get(f.actor, Operations.visit(f.actor, visit).session.ticket_id)

    next = open_visit(f)
    assert next != visit
    assert Operations.visit(f.actor, next).total == 0
    assert Operations.visit(f.actor, visit).session.total == 5100
    report = Operations.workspace(f.actor, Operations.today(f.actor)).report
    assert report.sales == 5100
    assert report.payments["pix"] == 5100
    assert report.open_count == 1
    assert [%{quantity: 2}] = report.consumption

    assert {:error, :invalid_state} =
             operation(f.actor, "submit_batch", %{
               "session_id" => visit,
               "lines" => [item(f.actor, f.soup)]
             })
  end

  test "cancellation excludes totals, creates an explicit destination notice and preserves original lines" do
    f = operations_fixture()
    visit = open_visit(f)

    {:ok, %{"ids" => [batch]}} =
      operation(f.actor, "submit_batch", %{
        "session_id" => visit,
        "lines" => [item(f.actor, f.soup)]
      })

    assert {:error, :invalid_values} =
             operation(f.actor, "cancel_batch", %{"batch_id" => batch, "reason" => " "})

    assert {:ok, %{"id" => cancellation}} =
             operation(f.actor, "cancel_batch", %{
               "batch_id" => batch,
               "reason" => "Cliente desistiu"
             })

    data = Operations.visit(f.actor, visit)
    assert data.total == 0
    assert [original, notice] = data.batches
    assert original.status == "cancelled"
    assert notice.kind == "cancellation"
    assert notice.source_id == original.id
    assert notice.destination == original.destination
    assert hd(notice.lines).name == hd(original.lines).name
    assert {:error, :invalid_state} = operation(f.actor, "print_ticket", %{"batch_id" => batch})

    assert {:error, :pending_handoff} =
             operation(f.actor, "settle", %{
               "session_id" => visit,
               "expected_total" => 0,
               "payment_method" => "cash"
             })

    assert {:ok, _} = operation(f.actor, "handoff", %{"batch_id" => cancellation})

    assert {:ok, _} =
             operation(f.actor, "settle", %{
               "session_id" => visit,
               "expected_total" => 0,
               "payment_method" => "cash"
             })

    assert Operations.workspace(f.actor, Operations.today(f.actor)).report.consumption == []
    assert Repo.aggregate(Line, :count) == 2
  end

  test "day close blocks outstanding earlier days and seals business dates without changing history" do
    f = operations_fixture()
    yesterday = Date.add(Operations.today(f.actor), -1)
    visit = open_visit(f, yesterday)

    assert {:error, :open_sessions} =
             operation(f.actor, "close_day", %{
               "business_date" => Date.to_iso8601(Operations.today(f.actor))
             })

    assert {:ok, _} =
             operation(f.actor, "settle", %{
               "session_id" => visit,
               "expected_total" => 0,
               "payment_method" => "cash"
             })

    assert {:ok, _} =
             operation(f.actor, "close_day", %{"business_date" => Date.to_iso8601(yesterday)})

    report = Operations.workspace(f.actor, yesterday).report
    assert report.closed.summary["settled_count"] == 1

    assert {:error, :day_closed} =
             operation(f.actor, "open_session", %{
               "resource_id" => f.resource,
               "responsible_actor" => "Carlos",
               "business_date" => Date.to_iso8601(yesterday)
             })

    assert open_visit(f) != visit
  end

  test "forged generic workflow transition cannot bypass operational settlement" do
    f = operations_fixture()
    visit = open_visit(f)
    ticket_id = Operations.visit(f.actor, visit).session.ticket_id
    cmd = Instantflow.WorkflowFixtures.transition_command(f.actor, ticket_id, "settle")
    assert {:error, :checkout_required} = WorkflowRuntime.command(f.actor, cmd)
    assert Repo.get!(Session, visit).status == "open"
  end

  test "catalog revision, inactive products, invalid quantities and money validation" do
    f = operations_fixture()
    visit = open_visit(f)
    product = Repo.get!(Product, f.soup)

    attrs = %{
      "id" => product.id,
      "revision" => product.revision,
      "name" => product.name,
      "price" => product.price,
      "category" => product.category,
      "destination" => product.destination,
      "active" => false
    }

    assert {:ok, _} = operation(f.actor, "save_product", attrs)
    assert {:error, :conflict} = operation(f.actor, "save_product", attrs)

    assert {:error, :inactive_product} =
             operation(f.actor, "submit_batch", %{
               "session_id" => visit,
               "lines" => [item(f.actor, f.soup)]
             })

    assert {:error, :invalid_values} =
             operation(f.actor, "submit_batch", %{
               "session_id" => visit,
               "lines" => [item(f.actor, f.asado, 0)]
             })

    assert {:ok, 2550} = Operations.parse_money("25,50")
    assert {:ok, 2550} = Operations.parse_money("25.5")
    assert :error = Operations.parse_money("1e4")
    assert :error = Operations.parse_money("-5")
  end

  test "non-admin and cross-tenant identifiers fail closed, including RLS and ownership constraints" do
    f = operations_fixture()
    other = staff_fixture("staff")
    assert Operations.workspace(other, Operations.today(f.actor)) == nil
    assert {:error, :forbidden} = operation(other, "add_resource", %{"name" => "Inválida"})

    org =
      Repo.insert!(%Instantflow.Identity.Organization{
        slug: "restaurante-outro",
        name: "Outro restaurante"
      })

    department =
      Repo.insert!(%Instantflow.Identity.Department{organization_id: org.id, name: "Operação"})

    membership =
      Repo.insert!(%Instantflow.Identity.Membership{
        organization_id: org.id,
        department_id: department.id,
        user_id: f.actor.user_id,
        role: "admin"
      })

    actor = Instantflow.Identity.scope(membership.user_id, org.id)
    visit = open_visit(f)
    assert Operations.visit(actor, visit) == nil
    assert Operations.workspace(actor, Operations.today(f.actor)) == nil

    assert {:error, :not_found} =
             operation(actor, "open_session", %{
               "workflow_id" => Operations.default_workflow(f.actor),
               "resource_id" => f.resource,
               "responsible_actor" => "Carlos",
               "business_date" => Date.to_iso8601(Operations.today(f.actor))
             })

    assert {:ok, []} = Tenant.transaction(actor, fn _ -> Repo.all(Product) end)
    assert Repo.aggregate(Receipt, :count) >= 4
  end
end
