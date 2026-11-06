defmodule Instantflow.AuthorizationEfficiencyTest do
  use Instantflow.DataCase, async: true
  import Instantflow.WorkflowFixtures
  alias Instantflow.{Identity, Tenant, WorkflowRuntime}
  alias Instantflow.Diagnostics.QueryProbe

  test "workflow reads and commands load authorization once, including receipt replay" do
    f = workflow_fixture()

    command = %{
      "operation" => "create",
      "workflow_id" => f.version.workflow_id,
      "key" => "single-authorization"
    }

    {{:ok, result}, created} =
      QueryProbe.capture(fn -> WorkflowRuntime.command(f.requester, command) end)

    assert created.groups.authorization.statements == 3

    {{:ok, ^result}, replay} =
      QueryProbe.capture(fn -> WorkflowRuntime.command(f.requester, command) end)

    assert replay.groups.authorization.statements == 3

    {{:ok, _}, read} =
      QueryProbe.capture(fn -> WorkflowRuntime.get(f.requester, result["ticket_id"]) end)

    assert read.groups.authorization.statements == 3

    assert {:ok, _} = Identity.revoke(f.admin, f.requester.id)
    assert {:error, :not_found} = WorkflowRuntime.get(f.requester, result["ticket_id"])
    assert {:error, :forbidden} = WorkflowRuntime.command(f.requester, command)
  end

  test "same-tenant nesting restores the enclosing settings and fixture role" do
    f = workflow_fixture()
    before = settings()

    assert {:ok, :ok} =
             Tenant.raw(f.requester.organization_id, fn ->
               scoped = settings()
               assert scoped == [["1", "instantflow_runtime"]]
               assert {:ok, ^scoped} = Tenant.raw(1, &settings/0)
               assert settings() == scoped
               :ok
             end)

    assert settings() == before

    assert_raise RuntimeError, "synthetic rollback", fn ->
      Tenant.raw(1, fn -> raise "synthetic rollback" end)
    end

    assert settings() == before
  end

  defp settings do
    Repo.query!(
      "SELECT NULLIF(current_setting('instantflow.organization_id', true), ''), current_user"
    ).rows
  end

  test "batch policy helpers require an enclosing transaction" do
    f = workflow_fixture()
    id = create_ticket(f)
    ticket = Repo.get!(Instantflow.WorkflowRuntime.Ticket, id)

    assert_raise ArgumentError, fn -> Instantflow.Access.load_many([f.requester]) end

    assert_raise ArgumentError, fn ->
      Instantflow.WorkflowRuntime.AccessFacts.load([f.requester], ticket, f.version)
    end
  end
end
