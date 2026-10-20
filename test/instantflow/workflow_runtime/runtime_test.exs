defmodule Instantflow.WorkflowRuntimeTest do
  use Instantflow.DataCase, async: true
  import Instantflow.WorkflowFixtures
  alias Instantflow.{Delivery, WorkflowCatalog, WorkflowRuntime}
  alias Instantflow.WorkflowRuntime.{Event, Receipt, Section, Ticket}
  alias Instantflow.WorkflowCatalog.Version
  alias Instantflow.Delivery.Message

  test "required fields, failed delivery, correction, resubmission and approval use the pinned definition" do
    f = workflow_fixture()
    id = create_ticket(f)
    assert {:error, :required_fields} = transition(f.requester, id, "submit")
    assert {:ok, _} = save(f.requester, id, values())
    assert {:ok, _} = transition(f.requester, id, "submit")
    assert {:error, :guard_failed} = transition(f.reviewer, id, "approve")
    Delivery.drain()

    message =
      Repo.one!(
        from m in Message, where: m.ticket_id == ^id and m.kind == "simulate_notification"
      )

    assert message.status == "failed"
    assert {:ok, _} = Delivery.retry(f.reviewer, message.id)
    Delivery.drain()
    assert {:error, :reason_required} = transition(f.reviewer, id, "request_correction")

    assert {:ok, _} =
             transition(f.reviewer, id, "request_correction", "Detalhar a justificativa.")

    assert Repo.get!(Ticket, id).return_stage == "review"

    assert {:ok, _} =
             save(f.requester, id, Map.put(values(), "justification", "Justificativa revisada."))

    assert {:ok, _} = transition(f.requester, id, "resubmit")
    assert {:ok, _} = transition(f.reviewer, id, "approve")
    assert Repo.get!(Ticket, id).stage == "approved"
    assert {:error, :forbidden} = save(f.requester, id, values())
    assert Repo.aggregate(Event, :count) == 7
  end

  test "duplicate commands replay results and mismatched payloads cannot duplicate effects" do
    f = workflow_fixture()
    command = %{"operation" => "create", "key" => key(), "workflow_id" => f.version.workflow_id}
    assert {:ok, result} = WorkflowRuntime.command(f.requester, command)
    assert {:ok, ^result} = WorkflowRuntime.command(f.requester, command)

    assert {:error, :idempotency_mismatch} =
             WorkflowRuntime.command(
               f.requester,
               Map.put(command, "workflow_id", f.version.workflow_id + 1)
             )

    assert Repo.aggregate(Ticket, :count) == 1
    assert Repo.aggregate(Receipt, :count) == 1
    assert Repo.aggregate(Message, :count) == 1
  end

  test "forged stage values, type errors, self approval, and stale review snapshots are denied" do
    f = workflow_fixture()
    id = create_ticket(f)

    assert {:error, :invalid_command} =
             WorkflowRuntime.command(
               f.requester,
               Map.put(transition_command(f.requester, id, "submit"), "stage", "approved")
             )

    assert {:error, {:invalid_values, _}} = save(f.requester, id, %{"summary" => 42})
    assert {:ok, _} = save(f.requester, id, values())
    stale = transition_command(f.requester, id, "submit")
    assert {:ok, _} = save(f.requester, id, Map.put(values(), "summary", "Resumo revisado"))
    assert {:error, :conflict} = WorkflowRuntime.command(f.requester, stale)
    assert {:ok, _} = transition(f.requester, id, "submit")
    assert {:error, :forbidden} = transition(f.requester, id, "approve")
    assert Repo.get!(Ticket, id).stage == "review"
  end

  test "rejection and cancellation require reasons and remain distinct terminal outcomes" do
    f = workflow_fixture()
    rejected = create_ticket(f)
    save(f.requester, rejected, values())
    transition(f.requester, rejected, "submit")
    assert {:ok, _} = transition(f.reviewer, rejected, "reject", "Fora do escopo.")
    assert Repo.get!(Ticket, rejected).stage == "rejected"
    cancelled = create_ticket(f)
    assert {:error, :reason_required} = transition(f.requester, cancelled, "cancel_draft")
    assert {:ok, _} = transition(f.requester, cancelled, "cancel_draft", "Solicitação duplicada.")
    assert Repo.get!(Ticket, cancelled).stage == "cancelled"
  end

  test "new publication preserves old tickets and rejects stale publishers" do
    f = workflow_fixture()
    id = create_ticket(f)
    changed = Map.put(f.definition, "name", "Aprovação versão dois")
    assert {:ok, v2} = WorkflowCatalog.publish(f.admin, changed, f.bindings, 1)
    assert {:error, :conflict} = WorkflowCatalog.publish(f.admin, changed, f.bindings, 1)
    assert Repo.get!(Ticket, id).workflow_version_id == f.version.id
    assert {:ok, _} = save(f.requester, id, values())
    assert {:ok, _} = transition(f.requester, id, "submit")
    assert Repo.get!(Ticket, create_ticket(f)).workflow_version_id == v2.id
  end

  test "database prevents published-version mutation" do
    f = workflow_fixture()

    assert_raise Postgrex.Error, ~r/immutable record/, fn ->
      Repo.transaction(fn ->
        Repo.update_all(from(v in Version, where: v.id == ^f.version.id), set: [number: 99])
      end)
    end
  end

  test "outer rollback leaves no partial ticket, section, history, receipt or outbox" do
    f = workflow_fixture()

    assert {:error, :injected_failure} =
             Repo.transaction(fn ->
               create_ticket(f)
               Repo.rollback(:injected_failure)
             end)

    for schema <- [Ticket, Section, Event, Receipt, Message],
        do: assert(Repo.aggregate(schema, :count) == 0)
  end

  test "outbox recovers an omitted post-commit refresh and duplicate processing is safe" do
    f = workflow_fixture()
    id = create_ticket(f)
    Phoenix.PubSub.subscribe(Instantflow.PubSub, Delivery.topic(id))
    refute_received {:ticket_changed, ^id}
    [message] = Repo.all(Message)
    assert {:ok, _} = Delivery.process(message.id)
    assert_receive {:ticket_changed, ^id}
    assert {:ok, :already_processed} = Delivery.process(message.id)
    refute_received {:ticket_changed, ^id}
    assert Repo.get!(Message, message.id).attempts == 1
  end
end
