defmodule Instantflow.Demo.SchoolTest do
  use Instantflow.DataCase, async: true
  alias Instantflow.Demo.School
  alias Instantflow.{Identity, WorkflowRuntime}
  alias Instantflow.Identity.{Organization, User}
  alias Instantflow.WorkflowCatalog.Version
  alias Instantflow.WorkflowRuntime.{Event, Ticket}
  import Instantflow.WorkflowFixtures, only: [transition: 3]

  @password "fictional-demo-password-123"

  test "populates authorized cases, valid financial history and a correction path; repeat preserves work" do
    report = School.install!(@password, Repo)
    assert [%{total: 8, stages: stages}] = report.versions

    assert stages == %{
             "draft" => 2,
             "academic" => 1,
             "finance" => 1,
             "purchase" => 1,
             "receiving" => 1,
             "complete" => 1,
             "cancelled" => 1
           }

    org = Repo.get_by!(Organization, slug: "horizonte")
    presenter = scope("admin", org.id)
    staff = scope("docente", org.id)
    assert WorkflowRuntime.search(presenter).total == 8
    assert WorkflowRuntime.search(staff).total == 1
    workflow_id = Repo.one!(from v in Version, select: v.workflow_id)
    board = Instantflow.WorkflowCatalog.Views.search(presenter, workflow_id, "board")
    assert length(board.rows) == 8

    assert Enum.all?(board.rows, fn row ->
             Enum.any?(
               row.cells,
               &(&1.key == "request.summary" and is_binary(&1.value) and &1.value != "")
             )
           end)

    assert length(Instantflow.WorkflowCatalog.Views.search(staff, workflow_id, "board").rows) == 1
    own = hd(WorkflowRuntime.search(staff).tickets)
    other = Repo.one!(from t in Ticket, where: t.stage == "finance")
    assert {:error, :not_found} = WorkflowRuntime.get(staff, other.id)
    assert {:ok, _} = transition(staff, own.id, "submit")
    assert {:error, :forbidden} = transition(staff, own.id, "academic_approve")
    assert {:ok, _} = transition(presenter, own.id, "academic_approve")
    assert {:ok, _} = transition(presenter, own.id, "reserve")

    corrected = Repo.one!(from t in Ticket, where: t.stage == "draft")
    {:ok, data} = WorkflowRuntime.get(presenter, corrected.id)
    assert "request" in data.editable

    assert Enum.any?(
             data.events,
             &(&1.operation == "revise_academic" and &1.from_stage == "academic")
           )

    assert Enum.any?(
             data.sections,
             &(&1.key == "request" and String.length(&1.values["summary"]) > 10)
           )

    before = snapshot()
    School.install!("different-demo-password-456", Repo)
    assert snapshot() == before
    assert {:ok, _} = Identity.authenticate("admin@escola.example", @password)

    assert {:error, :invalid_credentials} =
             Identity.authenticate("admin@escola.example", "different-demo-password-456")

    refute Enum.any?(presenter.grants, &(&1.role in ["dean", "counselor", "finance_reverser"]))
  end

  test "retired pins remain intact while a new supported publication becomes primary" do
    report = School.install!(@password, Repo)
    old = hd(report.versions)
    version = Repo.get!(Version, old.version_id)
    old_tickets = Repo.all(from t in Ticket, order_by: t.id)

    Repo.insert_all("retired_workflow_versions", [
      %{
        version_id: version.id,
        organization_id: version.organization_id,
        reason: "Synthetic retirement acceptance",
        inserted_at: DateTime.utc_now(:second)
      }
    ])

    report = School.install!(@password, Repo)
    assert [%{primary: false, total: 8}, %{primary: true, total: 8}] = report.versions

    assert Repo.all(from t in Ticket, where: t.workflow_version_id == ^version.id, order_by: t.id) ==
             old_tickets

    before = snapshot()
    School.install!(@password, Repo)
    assert snapshot() == before
  end

  test "fixture validation fails explicitly before creating data" do
    for password <- [nil, "short", String.duplicate("x", 129)] do
      assert_raise ArgumentError, fn -> School.install!(password, Repo) end
    end

    assert Repo.aggregate(Organization, :count) == 0
  end

  defp scope(prefix, org_id),
    do: Identity.scope(Repo.get_by!(User, email: prefix <> "@escola.example").id, org_id)

  defp snapshot do
    %{
      tickets: Repo.all(from t in Ticket, order_by: t.id),
      events: Repo.aggregate(Event, :count),
      receipts: Repo.aggregate(Instantflow.WorkflowRuntime.Receipt, :count),
      entries: Repo.all(from e in Instantflow.Finance.Entry, order_by: e.id),
      accounts: Repo.all(from a in Instantflow.Finance.Account, order_by: a.id),
      outbox: Repo.aggregate(Instantflow.Delivery.Message, :count),
      access_events: Repo.aggregate(Instantflow.Organizations.Event, :count)
    }
  end
end
