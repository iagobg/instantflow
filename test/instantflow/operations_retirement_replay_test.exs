defmodule Instantflow.OperationsRetirementReplayTest do
  use Instantflow.DataCase, async: true
  import Instantflow.OperationsFixtures
  import Instantflow.IdentityFixtures
  alias Instantflow.{Access, Operations, Repo}
  alias Instantflow.Operations.{Receipt, Session}
  alias Instantflow.WorkflowCatalog.Templates

  test "opening replay checks the result's retired version after a replacement publication" do
    f = operations_fixture()
    command = opening(f.actor, f.resource)
    assert {:ok, result} = Operations.command(f.actor, command)
    version = Operations.visit(f.actor, result["id"]).version
    retire(version)
    replacement = republish(f.actor, version)
    assert replacement.workflow_id == version.workflow_id
    assert replacement.id != version.id
    counts = {Repo.aggregate(Session, :count), Repo.aggregate(Receipt, :count)}

    assert {:error, :retired_version} = Operations.command(f.actor, command)

    assert {:error, :idempotency_mismatch} =
             Operations.command(f.actor, Map.put(command, "responsible_actor", "Changed"))

    assert counts == {Repo.aggregate(Session, :count), Repo.aggregate(Receipt, :count)}
  end

  test "supported opening replay uses pinned grants while new openings use current publication" do
    f = operations_fixture()
    old = Operations.workspace(f.actor, Operations.today(f.actor)).version
    original = republish(f.actor, old, ["admin", "operations"])
    operator = staff_fixture("staff")
    {:ok, _} = Access.grant(f.actor, operator.id, operator.department_id, "operations")
    grant = Repo.get_by!(Instantflow.Access.Grant, membership_id: operator.id, role: "operations")
    command = opening(operator, f.resource, original.workflow_id)
    assert {:ok, result} = Operations.command(operator, command)
    replacement = republish(f.actor, original, ["admin"])
    assert replacement.id != original.id
    counts = {Repo.aggregate(Session, :count), Repo.aggregate(Receipt, :count)}

    assert {:ok, ^result} = Operations.command(operator, command)

    assert {:error, :forbidden} =
             Operations.command(operator, Map.put(command, "key", Ecto.UUID.generate()))

    assert {:error, :idempotency_mismatch} =
             Operations.command(operator, Map.put(command, "responsible_actor", "Changed"))

    {:ok, _} = Access.revoke(f.actor, grant.id)
    assert {:error, :forbidden} = Operations.command(operator, command)
    retire(original)
    assert {:error, :forbidden} = Operations.command(operator, command)
    assert counts == {Repo.aggregate(Session, :count), Repo.aggregate(Receipt, :count)}
  end

  defp opening(actor, resource, workflow_id \\ nil) do
    command = %{
      "operation" => "open_session",
      "key" => Ecto.UUID.generate(),
      "resource_id" => resource,
      "responsible_actor" => "Captured operator",
      "business_date" => Date.to_iso8601(Operations.today(actor))
    }

    if workflow_id, do: Map.put(command, "workflow_id", workflow_id), else: command
  end

  defp republish(actor, version, roles \\ nil) do
    {:ok, draft} = Templates.clone(actor, version.id)

    bindings =
      if roles, do: put_in(draft.bindings, ["roles", "operator"], roles), else: draft.bindings

    {:ok, saved} = Templates.save(actor, draft.id, draft.revision, draft.definition, bindings)
    {:ok, replacement} = Templates.publish(actor, saved.id, saved.revision)
    replacement
  end

  defp retire(version) do
    Repo.insert_all("retired_workflow_versions", [
      %{
        version_id: version.id,
        organization_id: version.organization_id,
        reason: "Synthetic operator retirement fixture",
        inserted_at: DateTime.utc_now(:second) |> DateTime.to_naive()
      }
    ])
  end
end
