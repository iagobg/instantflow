defmodule Instantflow.Finance.AccountingTest do
  use Instantflow.DataCase, async: true
  import Instantflow.FinanceFixtures

  import Instantflow.WorkflowFixtures,
    only: [transition: 3, transition: 4, transition_command: 3, key: 0]

  alias Instantflow.{Finance, WorkflowRuntime}

  test "reservation converts without double subtraction, retry is safe, partial delivery cannot finish" do
    f = finance_fixture()
    id = request(f)
    cmd = transition_command(f.finance, id, "reserve")
    assert {:ok, result} = WorkflowRuntime.command(f.finance, cmd)
    assert {:ok, ^result} = WorkflowRuntime.command(f.finance, cmd)
    assert [%{reserved: 6000, spent: 0, available: 4000}] = Finance.accounts(f.finance)
    assert {:ok, _} = save(f.operations, id, "order", %{"reference" => "Pedido fictício"})
    assert {:ok, _} = transition(f.operations, id, "order")
    assert [%{reserved: 0, spent: 6000, available: 4000}] = Finance.accounts(f.finance)
    assert {:error, :invalid_delivery} = save(f.operations, id, "delivery", %{"received" => -1})
    assert {:error, :invalid_delivery} = save(f.operations, id, "delivery", %{"received" => 5})
    assert {:ok, _} = save(f.operations, id, "delivery", %{"received" => 2})
    assert {:error, :incomplete_delivery} = transition(f.operations, id, "finish")
    assert {:ok, _} = save(f.operations, id, "delivery", %{"received" => 4})
    assert {:ok, _} = transition(f.operations, id, "finish")
    assert [%{spent: 6000, available: 4000}] = Finance.accounts(f.finance)
  end

  test "pre-order cancellation releases once; explicit privileged reversal credits a posted order" do
    f = finance_fixture()
    id = request(f)
    assert {:ok, _} = transition(f.finance, id, "reserve")

    cmd =
      transition_command(f.operations, id, "cancel_purchase")
      |> Map.put("reason", "Cancelado antes do pedido")

    assert {:ok, result} = WorkflowRuntime.command(f.operations, cmd)
    assert {:ok, ^result} = WorkflowRuntime.command(f.operations, cmd)
    assert [%{reserved: 0, spent: 0, available: 10_000}] = Finance.accounts(f.finance)
    other = request(f)
    assert {:ok, _} = transition(f.finance, other, "reserve")
    assert {:ok, _} = save(f.operations, other, "order", %{"reference" => "Pedido 2"})
    assert {:ok, _} = transition(f.operations, other, "order")
    assert {:error, :forbidden} = transition(f.finance, other, "reverse_receiving", "Crédito")
    assert {:error, :reason_required} = transition(f.reverser, other, "reverse_receiving")

    assert {:ok, _} =
             transition(f.reverser, other, "reverse_receiving", "Crédito fictício confirmado")

    assert [%{reserved: 0, spent: 0, available: 10_000}] = Finance.accounts(f.finance)

    assert Enum.any?(
             Finance.entries(f.finance, f.account.id),
             &(&1.operation == "reverse" && &1.actor_id == f.reverser.user_id)
           )
  end

  test "revision releases hold, clears dependent work and repeats academic and finance approvals" do
    f = finance_fixture("field_trip")
    id = request(f)
    assert {:ok, _} = transition(f.finance, id, "reserve")
    assert {:ok, _} = save(f.operations, id, "order", %{"reference" => "Ônibus"})
    assert {:ok, _} = transition(f.operations, id, "revise_purchase", "Novo destino e custo")
    assert [%{available: 10_000}] = Finance.accounts(f.finance)
    {:ok, data} = WorkflowRuntime.get(f.requester, id)
    assert data.ticket.stage == "draft"
    assert Enum.find(data.sections, &(&1.key == "order")).values == %{}
    assert {:error, :forbidden} = transition(f.finance, id, "reserve")

    proposal =
      Enum.find(data.sections, &(&1.key == "request")).values |> Map.put("amount", 12_000)

    assert {:ok, _} = save(f.requester, id, "request", proposal)
    assert {:ok, _} = transition(f.requester, id, "submit")
    assert {:ok, _} = transition(f.head, id, "academic_approve")
    assert {:error, :insufficient_budget} = transition(f.finance, id, "reserve")
  end

  test "trip requires academic, finance, transport and safety steps" do
    f = finance_fixture("field_trip")
    id = request(f)
    assert {:error, :forbidden} = transition(f.safety, id, "approve")
    assert {:ok, _} = transition(f.finance, id, "reserve")
    assert {:error, :required_fields} = transition(f.operations, id, "order")
    assert {:ok, _} = save(f.operations, id, "order", %{"reference" => "Ônibus fictício"})
    assert {:ok, _} = transition(f.operations, id, "order")
    assert {:ok, _} = save(f.safety, id, "safety", %{"confirmed" => false})
    assert {:error, :guard_failed} = transition(f.safety, id, "approve")
    assert {:ok, _} = save(f.safety, id, "safety", %{"confirmed" => true})
    assert {:ok, _} = transition(f.safety, id, "approve")
    assert [%{spent: 6000, reserved: 0}] = Finance.accounts(f.finance)
  end

  test "allocation authority is separate, retries compare payload, and finance cannot self-approve" do
    f = finance_fixture()

    assert {:error, :forbidden} =
             Finance.allocate(f.admin, f.account.id, 50, "Sem permissão", key())

    token = key()
    assert {:ok, _} = Finance.allocate(f.finance, f.account.id, 50, "Ajuste", token)
    assert {:ok, _} = Finance.allocate(f.finance, f.account.id, 50, "Ajuste", token)

    assert {:error, :idempotency_mismatch} =
             Finance.allocate(f.finance, f.account.id, 51, "Ajuste", token)

    {:ok, _} =
      Instantflow.Access.grant(f.admin, f.requester.id, f.requester.department_id, "finance")

    id = request(f)
    assert {:error, :forbidden} = transition(f.requester, id, "reserve")
    assert Finance.accounts(f.requester) != []
  end
end
