defmodule Instantflow.CuratedCommunicationsTest do
  use Instantflow.DataCase, async: true

  alias Instantflow.{
    CuratedFixtures,
    Delivery,
    WorkflowRuntime,
    WorkflowFixtures,
    FinanceFixtures,
    BuilderFixtures,
    Participants,
    Tenant
  }

  alias Instantflow.Delivery.Curated

  test "curated simulation retries stop after three durable attempts" do
    f = CuratedFixtures.fixture("failure")
    {:ok, released} = CuratedFixtures.release(f)
    id = released["message_id"]

    for attempt <- 1..3 do
      assert {:ok, %{status: "failed", attempts: ^attempt}} = Delivery.process(1, id)
      if attempt < 3, do: assert({:ok, _} = Delivery.retry(f.admin, id))
    end

    assert {:error, :retry_limit} = Delivery.retry(f.admin, id)
    assert {:ok, :already_processed} = Delivery.process(1, id)
  end

  test "recipient inbox is SQL-paged without per-row policy queries, with post-authorization totals" do
    f = CuratedFixtures.fixture("success")
    {:ok, _} = CuratedFixtures.release(f)
    first = measured(fn -> Curated.inbox(f.recipient, f.version.workflow_id) end)
    for _ <- 1..27, do: {:ok, _} = CuratedFixtures.release(f)
    larger = measured(fn -> Curated.inbox(f.recipient, f.version.workflow_id) end)
    assert length(first.queries) == length(larger.queries)
    assert larger.result.total == 28 and length(larger.result.rows) == 25
    assert Enum.max(Enum.map(larger.queries, &(&1.result.num_rows || 0))) <= 25
    page = Curated.inbox(f.recipient, f.version.workflow_id, %{"page" => "2"})
    assert page.page == 2 and page.pages == 2 and length(page.rows) == 3

    assert MapSet.disjoint?(
             MapSet.new(page.rows, & &1.id),
             MapSet.new(larger.result.rows, & &1.id)
           )

    assert Curated.inbox(f.other, f.version.workflow_id).total == 0
    assert Curated.inbox(f.recipient, f.version.workflow_id, %{"page" => %{}}).page == 1
  end

  test "current author and recipient memberships fence queued work and a new publication cannot rewrite snapshots" do
    f = CuratedFixtures.fixture("success")
    {:ok, released} = CuratedFixtures.release(f)
    {:ok, draft} = Instantflow.WorkflowCatalog.Templates.clone(f.admin, f.version.id)
    d = put_in(draft.definition, ["communications", Access.at(0), "label"], "NEW-PUBLICATION")

    {:ok, saved} =
      Instantflow.WorkflowCatalog.Templates.save(f.admin, draft.id, draft.revision, d, f.bindings)

    {:ok, _} = Instantflow.WorkflowCatalog.Templates.publish(f.admin, saved.id, saved.revision)
    assert {:ok, %{status: "succeeded"}} = Delivery.process(1, released["message_id"])
    refute inspect(Curated.inbox(f.recipient, f.version.workflow_id)) =~ "NEW-PUBLICATION"
    {:ok, next} = CuratedFixtures.release(f)
    admin = Instantflow.IdentityFixtures.staff_fixture()
    {:ok, _} = Instantflow.Identity.revoke(admin, f.admin.id)
    assert {:ok, %{status: "cancelled"}} = Delivery.process(1, next["message_id"])
    {:ok, _} = Instantflow.Identity.revoke(admin, f.recipient.id)
    assert Curated.inbox(f.recipient, f.version.workflow_id).total == 0
  end

  test "shared identity and forged grants cannot expose another organization's releases" do
    f = CuratedFixtures.fixture("success")
    {:ok, release} = CuratedFixtures.release(f)

    org =
      Repo.insert!(%Instantflow.Identity.Organization{
        slug: "release-#{Ecto.UUID.generate()}",
        name: "Organização independente"
      })

    dept =
      Repo.insert!(%Instantflow.Identity.Department{
        organization_id: org.id,
        name: "Equipe local"
      })

    member =
      Repo.insert!(%Instantflow.Identity.Membership{
        organization_id: org.id,
        department_id: dept.id,
        user_id: f.recipient.user_id,
        role: "staff"
      })

    scope = Instantflow.Identity.scope(member.user_id, org.id)
    forged = %{scope | grants: [%{role: "admin", department_id: f.admin.department_id}]}
    assert Curated.inbox(forged, f.version.workflow_id).total == 0
    assert Curated.options(forged) == []
    assert {:error, :not_found} = Curated.retry(forged, release["message_id"])
    assert Instantflow.WorkflowCatalog.Workspaces.installed(scope) == []
  end

  defp measured(fun) do
    id = Ecto.UUID.generate()
    :telemetry.attach(id, [:instantflow, :repo, :query], &__MODULE__.capture/4, self())

    try do
      result = fun.()
      %{result: result, queries: drain([])}
    after
      :telemetry.detach(id)
    end
  end

  def capture(_, _, metadata, pid) do
    if self() == pid, do: send(pid, {:curated_query, Map.take(metadata, [:query, :result])})
  end

  defp drain(acc) do
    receive do
      {:curated_query, %{result: {:ok, result}} = metadata} ->
        drain([%{metadata | result: result} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "snapshot, failed retry, duplicate dispatch and guarded closure grant no internal access" do
    f = CuratedFixtures.fixture()
    assert {:error, :not_found} = WorkflowRuntime.get(f.recipient, f.id)
    assert WorkflowRuntime.search(f.recipient).total == 0
    assert {:error, :guard_failed} = WorkflowFixtures.transition(f.admin, f.id, "complete")
    key = Ecto.UUID.generate()
    {:ok, data} = WorkflowRuntime.get(f.admin, f.id)

    assert {:ok, released} =
             Curated.release(f.admin, f.id, "outcome", f.recipient.id, data.ticket.revision, key)

    assert {:ok, ^released} =
             Curated.release(f.admin, f.id, "outcome", f.recipient.id, data.ticket.revision, key)

    id = released["message_id"]
    assert hd(Curated.inbox(f.recipient, f.version.workflow_id).rows).content == []
    assert {:ok, %{status: "failed"}} = Delivery.process(1, id)
    assert {:ok, :already_processed} = Delivery.process(1, id)
    assert {:error, :forbidden} = Delivery.retry(f.recipient, id)

    assert {:ok, _} =
             FinanceFixtures.save(f.clerk, f.id, "request", %{"summary" => "CHANGED-PRIVATE"})

    assert {:ok, _} = Delivery.retry(f.admin, id)
    assert {:ok, %{status: "succeeded", attempts: 2}} = Delivery.process(1, id)
    inbox = Curated.inbox(f.recipient, f.version.workflow_id)
    assert inbox.total == 1
    assert inspect(inbox) =~ "RELEASED-ORIGINAL"
    refute inspect(inbox) =~ "CHANGED-PRIVATE"
    refute Map.has_key?(hd(inbox.rows), :ticket_id)
    assert Curated.inbox(f.other, f.version.workflow_id).total == 0
    assert {:ok, _} = WorkflowFixtures.transition(f.admin, f.id, "complete")
  end

  test "revocation before dispatch cancels content and hides status/counts; sender authority is live" do
    f = CuratedFixtures.fixture("success")
    {:ok, released} = CuratedFixtures.release(f)

    assert {:ok, _} =
             Participants.command(
               f.admin,
               BuilderFixtures.participant_command(f.id, f.recipient.id, "revoke", 2)
             )

    assert {:ok, %{status: "cancelled"}} = Delivery.process(1, released["message_id"])
    assert Curated.inbox(f.recipient, f.version.workflow_id).total == 0
    assert Curated.options(f.recipient) == []
    assert {:error, :ineligible_recipient} = CuratedFixtures.release(f)
    assert {:error, :guard_failed} = WorkflowFixtures.transition(f.admin, f.id, "complete")
  end

  test "ambiguous simulation requires explicit current authority and reason before closure" do
    f = CuratedFixtures.fixture("ambiguous")
    {:ok, released} = CuratedFixtures.release(f)
    id = released["message_id"]
    assert {:ok, %{status: "ambiguous"}} = Delivery.process(1, id)
    assert {:error, :not_failed} = Delivery.retry(f.admin, id)
    assert {:error, :invalid_state} = Curated.resolve(f.admin, id, "succeeded", "")
    assert {:error, :guard_failed} = WorkflowFixtures.transition(f.admin, f.id, "complete")

    assert {:ok, %{status: "succeeded"}} =
             Curated.resolve(f.admin, id, "succeeded", "Confirmação sintética")

    assert {:error, :invalid_state} = Curated.resolve(f.admin, id, "succeeded", "Repetido")
    assert {:ok, _} = WorkflowFixtures.transition(f.admin, f.id, "complete")

    assert {:ok, 2} =
             Tenant.transaction(f.admin, fn _ ->
               Repo.aggregate(
                 Ecto.Query.from(a in Instantflow.Delivery.Attempt,
                   where: a.outbox_message_id == ^id
                 ),
                 :count
               )
             end)
  end
end
