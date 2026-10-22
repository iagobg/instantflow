defmodule Instantflow.BuilderTransactionTest do
  use Instantflow.DataCase, async: false

  alias Instantflow.{
    Access,
    Finance,
    FinanceFixtures,
    WorkflowCatalog,
    WorkflowFixtures,
    WorkflowRuntime
  }

  alias Instantflow.WorkflowRuntime.{Event, Receipt}

  test "a late outbox failure rolls back finance, stage, audit and receipt; replay rechecks authority" do
    f = FinanceFixtures.finance_fixture()

    definition =
      f.version.definition
      |> Map.put("template_key", "composed_atomicity")

    {:ok, version} = WorkflowCatalog.publish(f.admin, definition, f.version.bindings)
    f = %{f | version: version}
    id = FinanceFixtures.request(f)
    command = WorkflowFixtures.transition_command(f.finance, id, "reserve")
    {:ok, before} = WorkflowRuntime.get(f.finance, id)
    event_count = Repo.aggregate(Event, :count)
    receipt_count = Repo.aggregate(Receipt, :count)
    balances = Finance.accounts(f.finance)
    previous = Application.fetch_env(:instantflow, :max_pending_deliveries_per_organization)

    on_exit(fn ->
      case previous do
        {:ok, value} ->
          Application.put_env(:instantflow, :max_pending_deliveries_per_organization, value)

        :error ->
          Application.delete_env(:instantflow, :max_pending_deliveries_per_organization)
      end
    end)

    Application.put_env(:instantflow, :max_pending_deliveries_per_organization, 0)
    assert {:error, :queue_full} = WorkflowRuntime.command(f.finance, command)
    assert {:ok, after_failure} = WorkflowRuntime.get(f.finance, id)
    assert after_failure.ticket == before.ticket
    assert after_failure.sections == before.sections
    assert Repo.aggregate(Event, :count) == event_count
    assert Repo.aggregate(Receipt, :count) == receipt_count
    assert Finance.accounts(f.finance) == balances

    Application.put_env(:instantflow, :max_pending_deliveries_per_organization, 1000)
    assert {:ok, result} = WorkflowRuntime.command(f.finance, command)
    assert {:ok, ^result} = WorkflowRuntime.command(f.finance, command)
    assert [%{reserved: 6000, available: 4000}] = Finance.accounts(f.finance)
    assert Repo.aggregate(Receipt, :count) == receipt_count + 1

    grant = Enum.find(f.finance.grants, &(&1.role == "finance"))
    assert {:ok, _} = Access.revoke(f.admin, grant.id)
    assert {:error, :forbidden} = WorkflowRuntime.command(f.finance, command)
    assert Repo.aggregate(Receipt, :count) == receipt_count + 1
  end
end
