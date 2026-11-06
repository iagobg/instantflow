defmodule Instantflow.DbEfficiencyTest do
  use InstantflowWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  import Instantflow.WorkflowFixtures
  alias Instantflow.{Repo, Tenant, WorkflowRuntime}
  alias Instantflow.Identity.{Membership, Organization, User}

  defp measure(label, fun) do
    {value, report} = Instantflow.Diagnostics.QueryProbe.capture(fun, scope: :all)

    if path = System.get_env("DB_EFFICIENCY_REPORT") do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, Jason.encode!(Map.put(report, :scenario, label)) <> "\n", [:append])
    end

    value
  end

  test "connected record lifecycle query counts", %{conn: conn} do
    f = workflow_fixture()
    id = create_ticket(f)
    conn = login(conn, f.requester)

    {:ok, view, _} =
      measure("record_mount_http_and_live", fn ->
        live(conn, "/o/horizonte/solicitacoes/#{id}")
      end)

    assert has_element?(view, "#section-form-request")
    measure("idle_heartbeat", fn -> render_hook(view, "heartbeat", %{}) end)

    measure("reason_change", fn ->
      render_hook(view, "reason", %{"action" => %{"reason" => "probe"}})
    end)

    measure("draft_change", fn ->
      view |> form("#section-form-request", section: values()) |> render_change()
    end)

    measure("save_submit", fn ->
      view |> form("#section-form-request", section: values()) |> render_submit()
    end)

    measure("ticket_invalidation", fn ->
      send(view.pid, {:ticket_changed, 1, id})
      render(view)
    end)
  end

  test "list invalidation cost grows with registered members" do
    f = workflow_fixture()
    id = create_ticket(f)

    measure("invalidation_3_members", fn ->
      Tenant.raw(1, fn -> WorkflowRuntime.invalidate_lists(1, id) end)
    end)

    for n <- 1..100 do
      user =
        Repo.insert!(%User{
          email: "probe-#{n}@synthetic.invalid",
          name: "Synthetic",
          password_hash: f.requester.user.password_hash
        })

      Repo.insert!(%Membership{
        organization_id: 1,
        user_id: user.id,
        department_id: f.requester.department_id,
        role: "staff"
      })
    end

    measure("invalidation_103_members", fn ->
      Tenant.raw(1, fn -> WorkflowRuntime.invalidate_lists(1, id) end)
    end)
  end

  test "idle dispatcher scales with all organizations" do
    _ = staff_fixture()
    measure("idle_drain_1_org", &Instantflow.Delivery.drain/0)

    for n <- 1..9 do
      Repo.insert!(%Organization{slug: "health-probe-#{n}", name: "Synthetic #{n}"})
    end

    measure("idle_drain_10_orgs", &Instantflow.Delivery.drain/0)
  end

  test "detail history growth measurement" do
    f = workflow_fixture()
    id = create_ticket(f)
    {:ok, initial} = measure("detail_1_event", fn -> WorkflowRuntime.get(f.requester, id) end)
    now = DateTime.utc_now(:second)

    rows =
      for revision <- 2..1001 do
        %{
          organization_id: 1,
          ticket_id: id,
          actor_id: f.requester.user_id,
          operation: "save:request",
          from_stage: "draft",
          to_stage: "draft",
          revision: revision,
          details: %{},
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(Instantflow.WorkflowRuntime.Event, rows)
    {:ok, grown} = measure("detail_1001_events", fn -> WorkflowRuntime.get(f.requester, id) end)
    assert length(grown.events) == length(initial.events) + 1000
  end

  test "document metadata result excludes content" do
    f = workflow_fixture()

    definition =
      f.definition
      |> Map.update!("template_key", &(&1 <> "_documents"))
      |> Map.put("capabilities", ["core", "documents"])

    definition =
      update_in(definition["sections"], fn [section | rest] ->
        [
          Map.update!(
            section,
            "fields",
            &(&1 ++
                [
                  %{
                    "key" => "proof",
                    "label" => "Proof",
                    "type" => "attachment",
                    "document_policy" => %{
                      "reviewers" => [
                        %{
                          "role" => "reviewer",
                          "scope" => "workflow_department",
                          "department_binding" => "review_department"
                        }
                      ],
                      "max_bytes" => 5_242_880,
                      "media_types" => ["application/pdf"]
                    }
                  }
                ])
          )
          | rest
        ]
      end)

    {:ok, version} = Instantflow.WorkflowCatalog.publish(f.admin, definition, f.bindings)
    id = create_ticket(%{f | version: version})
    bytes = "%PDF-1.4\n" <> Base.encode16(:crypto.strong_rand_bytes(524_288)) <> "\n%%EOF"

    {:ok, _} =
      Instantflow.PrivateDocuments.upload(
        f.requester,
        id,
        "request",
        "proof",
        "synthetic.pdf",
        bytes
      )

    list =
      measure("document_metadata_1mb", fn ->
        Instantflow.PrivateDocuments.list(f.requester, id)
      end)

    assert length(list) == 1
    refute Map.has_key?(hd(list), :content)
  end
end
