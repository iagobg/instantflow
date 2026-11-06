defmodule Instantflow.BackgroundWorkTest do
  use Instantflow.DataCase, async: false
  import Instantflow.WorkflowFixtures

  alias Instantflow.{
    Delivery,
    DocumentHistoryFixtures,
    Identity,
    Maintenance,
    PrivateDocuments,
    WorkflowCatalog,
    WorkflowRuntime
  }

  alias Instantflow.Diagnostics.QueryProbe
  alias Instantflow.Identity.{Department, Membership, Organization}
  alias Instantflow.Enrollment.Document

  setup do
    keys = [
      :delivery_organizations_per_pass,
      :delivery_batch_per_organization,
      :maintenance_batch_size
    ]

    saved = Map.new(keys, &{&1, Application.fetch_env(:instantflow, &1)})

    on_exit(fn ->
      for {key, value} <- saved do
        case value do
          {:ok, value} -> Application.put_env(:instantflow, key, value)
          :error -> Application.delete_env(:instantflow, key)
        end
      end
    end)

    :ok
  end

  test "empty discovery is one statement at 1, 10 and 1000 organizations" do
    Instantflow.IdentityFixtures.staff_fixture()

    for {range, count} <- [{[], 1}, {2..10, 10}, {11..1000, 1000}] do
      add_empty_organizations(range)
      {[], delivery} = measure("empty_delivery_#{count}", &Delivery.drain/0)

      {%{documents: 0, calculations: 0, failures: 0}, maintenance} =
        measure("empty_maintenance_#{count}", &Maintenance.sweep/0)

      assert delivery.statements == 1
      assert maintenance.statements == 1
    end
  end

  test "SQL budget for ten minutes of idle scheduled passes includes retention" do
    Instantflow.IdentityFixtures.staff_fixture()
    add_empty_organizations(2..10)

    {_, report} =
      measure("idle_ten_minute_schedule_model", fn ->
        for tick <- 1..2400 do
          assert Delivery.drain() == []
          if rem(tick, 240) == 0, do: Maintenance.sweep()
        end
      end)

    assert report.statements == 2410
    assert report.statements < 0.1 * 301 * 2400
  end

  test "a due core record is processed within the single-boundary SQL budget" do
    f = workflow_fixture()
    id = create_ticket(f)
    {[{1, {:ok, 1}}], report} = measure("single_record_dispatch", &Delivery.drain/0)
    assert report.statements <= 20
    assert report.errors == 0
    assert Repo.get!(Instantflow.WorkflowRuntime.Ticket, id).refreshed_revision == 1
    assert Delivery.pending_ids(1) == []
  end

  test "direct refresh delivery reuses the locked record and remains replay-safe" do
    f = workflow_fixture()
    id = create_ticket(f)
    [message] = Delivery.pending_ids(1)

    {{:ok, %{status: "succeeded"}}, report} =
      measure("direct_refresh_dispatch", fn ->
        Delivery.process(1, message)
      end)

    assert report.statements <= 18
    assert report.errors == 0
    assert Repo.get!(Instantflow.WorkflowRuntime.Ticket, id).refreshed_revision == 1
    assert {:ok, :already_processed} = Delivery.process(1, message)
    assert Repo.aggregate(Instantflow.Delivery.Attempt, :count) == 1
  end

  test "a flooded tenant cannot monopolize a rotating page" do
    f = workflow_fixture()
    first = create_ticket(f)
    {second_actor, second} = other_ticket(f, "second")
    {third_actor, third} = other_ticket(f, "third")
    save(f.requester, first, values())
    save(f.requester, first, Map.put(values(), "summary", "Backlog"))
    Application.put_env(:instantflow, :delivery_organizations_per_pass, 1)
    Application.put_env(:instantflow, :delivery_batch_per_organization, 1)
    a = Delivery.drain_page()
    b = Delivery.drain_page(a.cursor)
    c = Delivery.drain_page(b.cursor)

    assert [a.cursor, b.cursor, c.cursor] == [
             1,
             second_actor.organization_id,
             third_actor.organization_id
           ]

    assert Repo.aggregate(
             from(m in Instantflow.Delivery.Message,
               where: m.organization_id == 1 and m.status == "pending"
             ),
             :count
           ) == 2

    assert Delivery.pending_ids(second_actor.organization_id) == []
    assert Delivery.pending_ids(third_actor.organization_id) == []
    assert Repo.get!(Instantflow.WorkflowRuntime.Ticket, second).refreshed_revision == 1
    assert Repo.get!(Instantflow.WorkflowRuntime.Ticket, third).refreshed_revision == 1
    assert Delivery.drain_page(c.cursor).cursor == 1
  end

  test "suspension preserves due work and the calculation discovery contract is unchanged" do
    f = workflow_fixture()
    create_ticket(f)
    Repo.update_all(from(o in Organization, where: o.id == 1), set: [status: "suspended"])
    assert Delivery.drain() == []

    assert Repo.aggregate(
             from(m in Instantflow.Delivery.Message, where: m.status == "pending"),
             :count
           ) == 1

    Repo.update_all(from(o in Organization, where: o.id == 1), set: [status: "active"])
    assert [{1, {:ok, 1}}] = Delivery.drain()
    assert Repo.query!("SELECT id FROM dispatch_organizations()").rows == [[1]]
    assert Delivery.drain() == []
  end

  test "worker startup and restart recover persisted intents without a wakeup" do
    f = workflow_fixture()
    id = create_ticket(f)
    worker = start_supervised!({Delivery.Worker, name: :test_delivery_worker, interval: 60_000})
    assert :sys.get_state(worker).cursor == 1
    assert Delivery.pending_ids(1) == []
    stop_supervised!(Delivery.Worker)
    save(f.requester, id, values())
    assert length(Delivery.pending_ids(1)) == 1
    worker = start_supervised!({Delivery.Worker, name: :test_delivery_worker, interval: 60_000})
    assert :sys.get_state(worker).cursor == 1
    assert Delivery.pending_ids(1) == []
  end

  test "retention progresses in bounded batches without deliveries and preserves retired files" do
    f = DocumentHistoryFixtures.fixture(1)

    expired = %{
      f.template
      | status: "ready",
        content: Instantflow.EnrollmentFixtures.pdf(),
        expires_at: DateTime.add(DateTime.utc_now(:second), -60)
    }

    ids = DocumentHistoryFixtures.insert(expired, 5)
    Delivery.drain()
    assert Delivery.pending_ids(1) == []
    Application.put_env(:instantflow, :maintenance_batch_size, 2)
    assert %{documents: 2, failures: 0} = Maintenance.sweep()
    assert %{documents: 2, failures: 0} = Maintenance.sweep()
    remaining = Repo.all(from(d in Document, where: d.id in ^ids and d.status == "ready"))
    assert length(remaining) == 1

    Repo.insert_all("retired_workflow_versions", [
      %{
        version_id: f.version.id,
        organization_id: 1,
        reason: "Synthetic frozen history",
        inserted_at: DateTime.utc_now(:second)
      }
    ])

    assert %{documents: 0, calculations: 0} = Maintenance.sweep()
    assert {:ok, {0, nil}} = PrivateDocuments.purge_expired(1)
    assert Repo.get!(Document, hd(remaining).id).content == Instantflow.EnrollmentFixtures.pdf()
  end

  test "logical expiry frees the quota and hides readiness before cleanup runs" do
    f = DocumentHistoryFixtures.fixture(1)

    expired = %{
      f.template
      | status: "ready",
        content: Instantflow.EnrollmentFixtures.pdf(),
        expires_at: DateTime.add(DateTime.utc_now(:second), -60)
    }

    ids = DocumentHistoryFixtures.insert(expired, 20)

    assert Enum.all?(
             PrivateDocuments.list(f.visitor, f.ticket_id),
             &(&1.status in ["expired", "deleted"])
           )

    assert {:ok, _} =
             PrivateDocuments.upload(
               f.visitor,
               f.ticket_id,
               "customer_details",
               "evidence",
               "new.pdf",
               Instantflow.EnrollmentFixtures.pdf()
             )

    # Physical data still exists; the quota and download decisions do not depend on a sweep.
    assert Repo.get!(Document, hd(ids)).content != <<>>
    doc = Repo.get!(Document, hd(ids))
    assert {:error, :not_found} = PrivateDocuments.download(f.visitor, doc.object_key)
  end

  test "independently supervised retention recovers expired files on startup" do
    f = DocumentHistoryFixtures.fixture(1)

    expired = %{
      f.template
      | status: "quarantined",
        content: Instantflow.EnrollmentFixtures.pdf(),
        expires_at: DateTime.add(DateTime.utc_now(:second), -60)
    }

    [id] = DocumentHistoryFixtures.insert(expired, 1)
    Delivery.drain()

    worker =
      start_supervised!({Maintenance.Worker, name: :test_maintenance_worker, interval: 60_000})

    assert :sys.get_state(worker).cursor == 1
    assert Repo.get!(Document, id).content == <<>>
  end

  defp add_empty_organizations(range) do
    now = DateTime.utc_now(:second)

    rows =
      for n <- range,
          do: %{
            slug: "empty-#{n}",
            name: "Synthetic",
            status: "active",
            timezone: "UTC",
            inserted_at: now,
            updated_at: now
          }

    Repo.insert_all(Organization, rows)
  end

  defp other_ticket(f, key) do
    org = Repo.insert!(%Organization{slug: key, name: "Synthetic"})
    department = Repo.insert!(%Department{organization_id: org.id, name: "Synthetic"})

    Repo.insert!(%Membership{
      organization_id: org.id,
      user_id: f.requester.user_id,
      department_id: department.id,
      role: "admin"
    })

    actor = Identity.scope(f.requester.user_id, org.id)
    bindings = put_in(f.bindings, ["departments", "review_department"], department.id)
    {:ok, version} = WorkflowCatalog.publish(actor, f.definition, bindings)

    {:ok, result} =
      WorkflowRuntime.command(actor, %{
        "operation" => "create",
        "workflow_id" => version.workflow_id,
        "key" => Ecto.UUID.generate()
      })

    {actor, result["ticket_id"]}
  end

  defp measure(scenario, fun) do
    {result, report} = QueryProbe.capture(fun)

    if path = System.get_env("DB_EFFICIENCY_REPORT") do
      File.write!(path, Jason.encode!(Map.put(report, :scenario, scenario)) <> "\n", [:append])
    end

    {result, report}
  end
end
