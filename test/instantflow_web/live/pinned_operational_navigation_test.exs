defmodule InstantflowWeb.PinnedOperationalNavigationTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  import Instantflow.OperationsFixtures
  alias Instantflow.{Access, Operations, Repo}
  alias Instantflow.WorkflowCatalog.Templates

  test "removed pages and new role/payment mappings preserve pinned sessions with current revocation",
       %{conn: conn} do
    f = operations_fixture()
    operator = staff_fixture("staff")
    {:ok, {_, grant}} = Access.grant(f.actor, operator.id, operator.department_id, "operations")
    base = Operations.workspace(f.actor, Operations.today(f.actor)).version

    original =
      publish(
        f.actor,
        base,
        base.definition,
        put_in(base.bindings, ["roles", "operator"], ["admin", "operations"])
      )

    {:ok, %{"id" => id}} =
      operation(operator, "open_session", %{
        "workflow_id" => original.workflow_id,
        "resource_id" => f.resource,
        "responsible_actor" => "Pinned operator",
        "business_date" => Operations.today(operator)
      })

    changed =
      original.definition
      |> put_in(["interface", "pages", Elixir.Access.at(0), "key"], "current_desk")
      |> put_in(["interface", "operations", "payment_methods"], ["cash"])

    latest =
      publish(
        f.actor,
        original,
        changed,
        put_in(original.bindings, ["roles", "operator"], ["admin"])
      )

    other = install_operations(f.actor, "another_counter", "Another counter")
    assert Operations.version_for_visit(operator, id, other.workflow_id) == nil

    assert Operations.workspace(operator, Operations.today(operator), other.workflow_id, id) ==
             nil

    assert Operations.version_for_visit(operator, id, original.workflow_id).id == original.id

    assert Operations.workspace(operator, Operations.today(operator), original.workflow_id, id).version.id ==
             original.id

    old_url = ~p"/o/horizonte/processos/#{original.workflow_id}/p/overview/atendimentos/#{id}"
    {:ok, view, _} = live(login(conn, operator), old_url)
    assert has_element?(view, "#active-visit", "Pinned operator")
    assert has_element?(view, "#checkout_payment_method option[value='pix']")
    assert has_element?(view, "#pinned-session-rules")
    refute has_element?(view, "#open-visit-form")
    refute has_element?(view, "#product-form")
    refute has_element?(view, "#close-day")
    render_click(view, "reconcile", %{})
    assert has_element?(view, "#checkout_payment_method option[value='pix']")

    assert {:error, {:live_redirect, _}} =
             live(login(build_conn(), operator), ~p"/o/horizonte/processos/#{latest.workflow_id}")

    before_receipts = Repo.aggregate(Instantflow.Operations.Receipt, :count)
    {:ok, _} = Access.revoke(f.actor, grant.id)
    assert_redirect(view, ~p"/o/horizonte/processos")
    assert Operations.version_for_visit(operator, id, original.workflow_id) == nil

    assert Operations.workspace(operator, Operations.today(operator), original.workflow_id, id) ==
             nil

    assert {:error, :forbidden} =
             operation(operator, "settle", %{
               "workflow_id" => original.workflow_id,
               "session_id" => id,
               "expected_total" => 0,
               "payment_method" => "pix"
             })

    assert Repo.aggregate(Instantflow.Operations.Receipt, :count) == before_receipts
    {:ok, _} = Access.grant(f.actor, operator.id, operator.department_id, "operations")
    {:ok, restored, _} = live(login(build_conn(), operator), old_url)
    restored |> form("#checkout-form", checkout: %{payment_method: "pix"}) |> render_submit()
    assert has_element?(restored, "#visit-settled")
    assert Operations.visit(operator, id, original.workflow_id).session.payment_method == "pix"

    {:ok, %{"id" => next}} =
      operation(f.actor, "open_session", %{
        "workflow_id" => latest.workflow_id,
        "resource_id" => f.resource,
        "responsible_actor" => "Current operator",
        "business_date" => Operations.today(f.actor)
      })

    {:ok, current, _} =
      live(
        login(build_conn(), f.actor),
        ~p"/o/horizonte/processos/#{latest.workflow_id}/p/current_desk/atendimentos/#{next}"
      )

    assert has_element?(current, "#checkout_payment_method option[value='cash']")
    refute has_element?(current, "#checkout_payment_method option[value='pix']")
    assert Operations.visit(f.actor, next, latest.workflow_id).version.id == latest.id
  end

  test "archived sessions that predate capability declarations retain read-only batch history", %{
    conn: conn
  } do
    f = operations_fixture()
    original = Operations.workspace(f.actor, Operations.today(f.actor)).version

    definition =
      original.definition |> Map.delete("interface") |> Map.put("capabilities", ["core"])

    archived =
      Repo.insert!(%Instantflow.WorkflowCatalog.Version{
        organization_id: f.actor.organization_id,
        workflow_id: original.workflow_id,
        number: 2,
        definition: definition,
        bindings: original.bindings,
        published_by_id: f.actor.user_id
      })

    ticket =
      Repo.insert!(%Instantflow.WorkflowRuntime.Ticket{
        organization_id: f.actor.organization_id,
        workflow_id: original.workflow_id,
        workflow_version_id: archived.id,
        requester_id: f.actor.user_id,
        assigned_department_id: f.actor.department_id,
        stage: "open"
      })

    now = DateTime.utc_now(:second)

    session =
      Repo.insert!(%Instantflow.Operations.Session{
        organization_id: f.actor.organization_id,
        workflow_id: original.workflow_id,
        resource_id: f.resource,
        ticket_id: ticket.id,
        resource_name: "Captured resource",
        waiter: "Captured historical actor",
        status: "archived",
        business_date: Operations.today(f.actor),
        opened_at: now
      })

    batch =
      Repo.insert!(%Instantflow.Operations.Batch{
        organization_id: f.actor.organization_id,
        workflow_id: original.workflow_id,
        session_id: session.id,
        destination: "Captured kitchen",
        waiter: session.waiter,
        status: "archived",
        inserted_at: now
      })

    Repo.insert!(%Instantflow.Operations.Line{
      organization_id: f.actor.organization_id,
      workflow_id: original.workflow_id,
      batch_id: batch.id,
      product_id: f.soup,
      name: "Captured historical soup",
      unit_price: 600,
      quantity: 2,
      notes: "Retained"
    })

    Repo.insert_all("retired_workflow_versions", [
      %{
        version_id: archived.id,
        organization_id: f.actor.organization_id,
        reason: "Actual historical session lineage fixture",
        inserted_at: DateTime.to_naive(now)
      }
    ])

    {:ok, view, _} =
      live(
        login(conn, f.actor),
        ~p"/o/horizonte/processos/#{original.workflow_id}/p/overview/atendimentos/#{session.id}"
      )

    assert has_element?(view, "#archived-operations")
    assert has_element?(view, "#active-visit", session.waiter)
    assert has_element?(view, "#fulfillment-batches", "Captured historical soup")
    assert has_element?(view, "#fulfillment-batches", "R$ 12,00")
    refute has_element?(view, "#checkout-form")
    refute has_element?(view, "#open-visit-form")
    refute has_element?(view, "#product-form")
    refute has_element?(view, "#print-batch-#{batch.id}")
    assert Operations.visit(f.actor, session.id, original.workflow_id).archived?
  end

  defp publish(actor, previous, definition, bindings) do
    {:ok, draft} = Templates.clone(actor, previous.id)
    {:ok, saved} = Templates.save(actor, draft.id, draft.revision, definition, bindings)
    {:ok, version} = Templates.publish(actor, saved.id, saved.revision)
    version
  end
end
