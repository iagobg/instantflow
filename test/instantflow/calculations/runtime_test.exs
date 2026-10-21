defmodule Instantflow.Calculations.RuntimeTest do
  use Instantflow.DataCase, async: false
  alias Instantflow.{Access, CalculationFixtures, Calculations, Tenant, WorkflowRuntime}
  alias Instantflow.Calculations.{Catalogue, Run}
  import Instantflow.WorkflowFixtures

  setup do
    Application.put_env(:instantflow, :calculation_execution, true)
    Application.put_env(:instantflow, :calculation_runner, CalculationFixtures)
    CalculationFixtures.switch(true)

    on_exit(fn ->
      Application.delete_env(:instantflow, :calculation_execution)
      Application.delete_env(:instantflow, :calculation_runner)
    end)

    :ok
  end

  test "transition queues an intent, required result blocks approval, allowed output applies once" do
    %{f: f, id: id} = CalculationFixtures.fixture()
    assert {:error, :calculation_required} = transition(f.reviewer, id, "approve")
    %{run: run, request: request} = CalculationFixtures.claim()

    assert {:ok, "succeeded"} =
             Calculations.finalize(
               1,
               run.id,
               run.fence,
               request,
               CalculationFixtures.response(request)
             )

    assert {:error, :stale_attempt} =
             Calculations.finalize(
               1,
               run.id,
               run.fence,
               request,
               CalculationFixtures.response(request)
             )

    {:ok, data} = WorkflowRuntime.get(f.requester, id)
    assert Enum.find(data.sections, &(&1.key == "quotation")).values == %{"total" => 8100}
    assert "quotation" not in data.editable
    assert {:ok, _} = transition(f.reviewer, id, "approve")
  end

  test "changed inputs and cancellation reject a late successful result" do
    %{f: f, id: id} = CalculationFixtures.fixture()
    %{run: run, request: request} = CalculationFixtures.claim()
    assert {:ok, _} = save(f.requester, id, %{"participants" => 82})

    assert {:error, :stale_attempt} =
             Calculations.finalize(
               1,
               run.id,
               run.fence,
               request,
               CalculationFixtures.response(request)
             )

    assert {:error, :calculation_required} = transition(f.reviewer, id, "approve")
    assert {:ok, "stale"} = Tenant.raw(1, fn -> Repo.get!(Run, run.id).status end)
  end

  test "revoked execution permission and disabled scripts prevent application" do
    %{f: f} = CalculationFixtures.fixture()
    %{run: run, request: request} = CalculationFixtures.claim()
    member = Instantflow.Identity.scope(f.requester.user_id, 1)
    grant = Enum.find(member.grants, &(&1.role == "python_execute"))
    assert {:ok, _} = Access.revoke(f.admin, grant.id)

    assert {:ok, "stale"} =
             Calculations.finalize(
               1,
               run.id,
               run.fence,
               request,
               CalculationFixtures.response(request)
             )
  end

  test "wrong tenant responses and undeclared output fields fail closed; retries keep logical identity" do
    %{f: f, id: id} = CalculationFixtures.fixture()
    %{run: run, request: request} = CalculationFixtures.claim()
    {:ok, forged} = CalculationFixtures.response(request)

    assert {:ok, "failed"} =
             Calculations.finalize(
               1,
               run.id,
               run.fence,
               request,
               {:ok, Map.put(forged, "organization_id", 2)}
             )

    assert {:ok, :ok} = Calculations.control(f.requester, run.id, "retry")
    %{run: second, request: second_request} = CalculationFixtures.claim()
    assert second.id == run.id
    refute second.fence == run.fence

    assert {:ok, "failed"} =
             Calculations.finalize(
               1,
               second.id,
               second.fence,
               second_request,
               CalculationFixtures.response(second_request, %{"total" => 1, "approve" => 1})
             )

    assert {:error, :calculation_required} = transition(f.reviewer, id, "approve")
    assert {:ok, :ok} = Calculations.control(f.requester, run.id, "cancel")
    assert {:error, :calculation_required} = Calculations.control(f.requester, run.id, "retry")
  end

  test "expired lease fences old worker and recovers at most three attempts" do
    CalculationFixtures.fixture()
    %{run: old, request: request} = CalculationFixtures.claim()

    {:ok, _} =
      Tenant.raw(1, fn ->
        Repo.update!(
          Ecto.Changeset.change(old, lease_until: DateTime.add(DateTime.utc_now(), -1))
        )
      end)

    %{run: run} = CalculationFixtures.claim()
    assert run.id == old.id and run.attempts == 2

    assert {:error, :stale_attempt} =
             Calculations.finalize(
               1,
               old.id,
               old.fence,
               request,
               CalculationFixtures.response(request)
             )

    assert {:error, :empty} = Calculations.claim(1)

    {:ok, _} =
      Tenant.raw(1, fn ->
        Repo.update!(
          Ecto.Changeset.change(run, lease_until: DateTime.add(DateTime.utc_now(), -1))
        )
      end)

    %{run: third} = CalculationFixtures.claim()
    assert third.attempts == 3

    {:ok, _} =
      Tenant.raw(1, fn ->
        Repo.update!(
          Ecto.Changeset.change(third, lease_until: DateTime.add(DateTime.utc_now(), -1))
        )
      end)

    assert {:ok, :discarded} = Calculations.claim(1)
    assert {:ok, "failed"} = Tenant.raw(1, fn -> Repo.get!(Run, run.id).status end)
  end

  test "organization suspension rejects claims and in-flight results" do
    CalculationFixtures.fixture()
    %{run: run, request: request} = CalculationFixtures.claim()

    Repo.get!(Instantflow.Identity.Organization, 1)
    |> Ecto.Changeset.change(status: "suspended")
    |> Repo.update!()

    assert {:error, :unavailable} = Calculations.claim(1)

    assert {:error, :unavailable} =
             Calculations.finalize(
               1,
               run.id,
               run.fence,
               request,
               CalculationFixtures.response(request)
             )
  end

  test "terminal payload retention clears snapshots without deleting audit identity" do
    CalculationFixtures.fixture()
    %{run: run, request: request} = CalculationFixtures.claim()

    assert {:ok, "succeeded"} =
             Calculations.finalize(
               1,
               run.id,
               run.fence,
               request,
               CalculationFixtures.response(request)
             )

    Repo.get!(Run, run.id)
    |> Ecto.Changeset.change(inserted_at: DateTime.add(DateTime.utc_now(), -8, :day))
    |> Repo.update!()

    assert {:ok, {1, nil}} = Calculations.purge_expired(1)

    assert {:ok, %{snapshot: %{}, output: nil, status: "stale", script_id: script_id}} =
             Tenant.raw(1, fn -> Repo.get!(Run, run.id) end)

    assert script_id == run.script_id
  end

  test "global kill switch rejects in-flight results even after re-enabling" do
    CalculationFixtures.fixture()
    %{run: run, request: request} = CalculationFixtures.claim()
    CalculationFixtures.switch(false)

    assert {:error, :execution_disabled} =
             Calculations.finalize(
               1,
               run.id,
               run.fence,
               request,
               CalculationFixtures.response(request)
             )

    CalculationFixtures.switch(true)

    assert {:ok, "stale"} =
             Calculations.finalize(
               1,
               run.id,
               run.fence,
               request,
               CalculationFixtures.response(request)
             )
  end

  test "script disablement invalidates pending results and required success" do
    %{f: f, script: script} = CalculationFixtures.fixture()
    %{run: run, request: request} = CalculationFixtures.claim()
    assert {:ok, :ok} = Catalogue.activate(f.admin, script.id, false)

    assert {:ok, "stale"} =
             Calculations.finalize(
               1,
               run.id,
               run.fence,
               request,
               CalculationFixtures.response(request)
             )
  end
end
