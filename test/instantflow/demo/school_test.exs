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

    assert %{total: 8, stages: stages} =
             Enum.find(report.versions, &(&1.workflow == "requisition"))

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
    assert WorkflowRuntime.search(presenter).total == 26
    assert WorkflowRuntime.search(staff).total == 1
    workflow_id = Repo.get!(Version, hd(report.versions).version_id).workflow_id
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

    other =
      Repo.one!(from t in Ticket, where: t.workflow_id == ^workflow_id and t.stage == "finance")

    assert {:error, :not_found} = WorkflowRuntime.get(staff, other.id)
    assert {:ok, _} = transition(staff, own.id, "submit")
    assert {:error, :forbidden} = transition(staff, own.id, "academic_approve")
    assert {:ok, _} = transition(presenter, own.id, "academic_approve")
    assert {:ok, _} = transition(presenter, own.id, "reserve")

    corrected =
      Repo.one!(from t in Ticket, where: t.workflow_id == ^workflow_id and t.stage == "draft")

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

    old_tickets =
      Repo.all(from t in Ticket, where: t.workflow_version_id == ^version.id, order_by: t.id)

    Repo.insert_all("retired_workflow_versions", [
      %{
        version_id: version.id,
        organization_id: version.organization_id,
        reason: "Synthetic retirement acceptance",
        inserted_at: DateTime.utc_now(:second)
      }
    ])

    report = School.install!(@password, Repo)

    assert [%{primary: false, total: 8}, %{primary: true, total: 8}] =
             Enum.filter(report.versions, &(&1.workflow == "requisition"))

    assert Repo.all(from t in Ticket, where: t.workflow_version_id == ^version.id, order_by: t.id) ==
             old_tickets

    before = snapshot()
    School.install!(@password, Repo)
    assert snapshot() == before
  end

  test "expanded school has valid documents, simulated retries and private incident assignments" do
    report = School.install!(@password, Repo)

    assert Map.new(report.versions, &{&1.workflow, &1.total}) ==
             %{"requisition" => 8, "enrollment" => 12, "field_trip" => 6, "incident" => 3}

    assert length(report.roles) == 8
    assert length(Enum.uniq_by(report.roles, & &1.email)) == 8
    org = Repo.get_by!(Organization, slug: "horizonte")
    presenter = scope("admin", org.id)
    staff = scope("docente", org.id)
    family = scope("familia", org.id)
    dean = scope("direcao", org.id)
    counselor = scope("orientacao", org.id)
    author = scope("compras", org.id)
    enrollment = Enum.find(report.versions, &(&1.workflow == "enrollment"))

    enrollment_version = Repo.get!(Version, enrollment.version_id)

    enrollment_board =
      Instantflow.WorkflowRuntime.StageBoards.read(
        presenter,
        enrollment_version.workflow_id,
        "board",
        %{}
      )

    assert enrollment_board.total == 12

    assert Enum.all?(enrollment_board.rows, fn row ->
             Enum.any?(row.cells, &(&1.key == "application.student_name" and is_binary(&1.value)))
           end)

    assert enrollment.stages == %{
             "draft" => 2,
             "documents" => 2,
             "correction" => 1,
             "academic" => 2,
             "payment" => 2,
             "provisioning" => 2,
             "complete" => 1
           }

    assert Repo.aggregate(Instantflow.Enrollment.Document, :count) == 12

    assert Repo.aggregate(
             from(d in Instantflow.Enrollment.Document, where: d.status == "ready"),
             :count
           ) == 7

    completed =
      Repo.one!(
        from t in Ticket,
          where: t.workflow_version_id == ^enrollment.version_id and t.stage == "complete"
      )

    {:ok, portal} =
      WorkflowRuntime.ParticipantPages.get(
        family,
        completed.workflow_id,
        "family_portal",
        completed.id
      )

    refute inspect(portal) =~ "Avaliação interna fictícia"
    {:ok, family_data} = WorkflowRuntime.get(family, completed.id)
    assert Enum.map(family_data.sections, & &1.key) == ["application"]
    assert {:error, :not_found} = WorkflowRuntime.get(staff, completed.id)

    provisioning =
      Repo.all(
        from m in Instantflow.Delivery.Message,
          where: m.kind == "simulate_provisioning",
          order_by: m.id
      )

    assert Enum.frequencies_by(provisioning, & &1.status) == %{"failed" => 2, "succeeded" => 1}
    assert Enum.find(provisioning, &(&1.status == "succeeded")).attempts == 2

    incident = Enum.find(report.versions, &(&1.workflow == "incident"))
    tickets = Repo.all(from t in Ticket, where: t.workflow_version_id == ^incident.version_id)

    for ticket <- tickets do
      assert {:error, :not_found} = WorkflowRuntime.get(presenter, ticket.id)
      assert {:error, :not_found} = WorkflowRuntime.get(staff, ticket.id)
      assert {:error, :not_found} = WorkflowRuntime.get(family, ticket.id)
      {:ok, data} = WorkflowRuntime.get(dean, ticket.id)
      refute Enum.any?(data.sections, &(&1.key == "support"))
      {:ok, reporter_data} = WorkflowRuntime.get(author, ticket.id)
      assert Enum.map(reporter_data.sections, & &1.key) == ["report"]

      if ticket.stage == "triage" do
        assert {:error, :not_found} = WorkflowRuntime.get(counselor, ticket.id)
      else
        {:ok, assigned_data} = WorkflowRuntime.get(counselor, ticket.id)
        notes = Enum.find(assigned_data.sections, &(&1.key == "support"))
        assert notes.values["notes"] =~ "Nota privada fictícia"
        refute Enum.any?(assigned_data.sections, &(&1.key in ["discipline", "communication"]))
      end
    end

    # An edited new scenario stays edited, with no duplicate documents or attempts.
    trip = Enum.find(report.versions, &(&1.workflow == "field_trip"))

    draft =
      Repo.one!(
        from t in Ticket, where: t.workflow_version_id == ^trip.version_id and t.stage == "draft"
      )

    assert {:ok, _} = transition(author, draft.id, "submit")
    before = snapshot()
    School.install!(@password, Repo)
    assert snapshot() == before
  end

  test "known enrollment board upgrade publishes without rewriting previous pins" do
    report = School.install!(@password, Repo)
    org = Repo.get_by!(Organization, slug: "horizonte")
    presenter = scope("admin", org.id)
    current = Enum.find(report.versions, &(&1.workflow == "enrollment"))
    current_version = Repo.get!(Version, current.version_id)

    previous_tickets =
      Repo.all(
        from t in Ticket, where: t.workflow_version_id == ^current.version_id, order_by: t.id
      )

    {:ok, old_style} =
      Instantflow.WorkflowCatalog.publish(
        presenter,
        Instantflow.Examples.definition("enrollment"),
        current_version.bindings,
        current_version.number
      )

    report = School.install!(@password, Repo)
    enrollments = Enum.filter(report.versions, &(&1.workflow == "enrollment"))

    assert [
             %{primary: false, total: 12},
             %{primary: false, total: 0},
             %{primary: true, total: 12}
           ] = enrollments

    assert Repo.get!(Version, old_style.id).definition ==
             Instantflow.Examples.definition("enrollment")

    assert Repo.all(
             from t in Ticket, where: t.workflow_version_id == ^current.version_id, order_by: t.id
           ) == previous_tickets

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
      documents: Repo.all(from d in Instantflow.Enrollment.Document, order_by: d.id),
      attempts: Repo.all(from a in Instantflow.Delivery.Attempt, order_by: a.id),
      relationships: Repo.all(from r in Instantflow.Participants.Relationship, order_by: r.id),
      access_events: Repo.aggregate(Instantflow.Organizations.Event, :count)
    }
  end
end
