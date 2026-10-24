defmodule InstantflowWeb.Sprint10EquipmentRecreationTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures

  alias Instantflow.{
    BuilderFixtures,
    Sprint10RecreationFixtures,
    Operations,
    Participants,
    WorkflowRuntime,
    FinanceFixtures,
    PrivateDocuments,
    Delivery,
    Repo
  }

  alias Instantflow.WorkflowCatalog.{Templates, Interchange, Version}

  test "blank equipment desk composes parts, invited correction, documents, views and curated messages" do
    admin = staff_fixture()

    customer =
      BuilderFixtures.invite_external(admin, "equipment-#{Ecto.UUID.generate()}@example.test")

    d = Sprint10RecreationFixtures.equipment()
    {:ok, draft} = Templates.import(admin, Interchange.encode(d))
    {:ok, editor, _} = live(login(build_conn(), admin), ~p"/o/horizonte/modelos/#{draft.id}")

    editor
    |> form("#template-mappings",
      mapping: %{
        roles: %{technician: ["admin"], customer: ["external"]},
        departments: %{workshop: admin.department_id},
        assignment: "workshop"
      }
    )
    |> render_submit()

    refute has_element?(editor, "#publish-template[disabled]")
    editor |> element("#publish-template") |> render_click()
    editor |> element("#confirm-publish-template") |> render_click()
    {:ok, draft} = Templates.get(admin, draft.id)
    v = Repo.get!(Version, draft.published_version_id)

    operation = fn op, params ->
      Operations.command(
        admin,
        Map.merge(params, %{
          "operation" => op,
          "workflow_id" => v.workflow_id,
          "key" => Ecto.UUID.generate()
        })
      )
    end

    {:ok, resource} = operation.("add_resource", %{"name" => "Bancada configurada"})

    {:ok, product} =
      operation.("save_product", %{
        "name" => "Peça sintética",
        "category" => "Reposição",
        "price" => 500,
        "destination" => "Oficina"
      })

    {:ok, opened} =
      operation.("open_session", %{
        "resource_id" => resource["id"],
        "responsible_actor" => "Técnico",
        "business_date" => Date.to_iso8601(Operations.today(admin))
      })

    session = Operations.visit(admin, opened["id"], v.workflow_id).session
    id = session.ticket_id

    for {op, rev} <- [{"create", 0}, {"verify", 1}] do
      assert {:ok, _} =
               Participants.command(
                 admin,
                 BuilderFixtures.participant_command(id, customer.id, op, rev)
                 |> Map.put("relationship", "owner")
               )
    end

    [{_, reference}] = Participants.Directory.options(admin, id, "work_order", "customer_link")

    {:ok, _} =
      FinanceFixtures.save(admin, id, "work_order", %{
        "customer_link" => reference,
        "fault_report" => "Resultado autorizado"
      })

    {:ok, _} =
      Instantflow.WorkflowFixtures.transition(admin, id, "request_details", "Envie o comprovante")

    {:ok, portal, _} =
      live(
        login(build_conn(), customer),
        ~p"/o/horizonte/processos/#{v.workflow_id}/participacao/customer/registros/#{id}"
      )

    portal
    |> form("[id='participant-field-repair_packet.fault']", field: %{value: "Defeito sintético"})
    |> render_submit()

    upload =
      file_input(portal, "#participant-upload", :document, [
        %{
          name: "equipment.pdf",
          content: Instantflow.EnrollmentFixtures.pdf(),
          type: "application/pdf",
          last_modified: 1
        }
      ])

    render_upload(upload, "equipment.pdf")

    portal
    |> form("#participant-upload", upload: %{target: "repair_packet.proof"})
    |> render_submit()

    [doc] = PrivateDocuments.list(admin, id)
    {:ok, _} = PrivateDocuments.review(admin, doc.object_key, true)
    send(portal.pid, :reconcile)
    assert has_element?(portal, "#participant-download-#{doc.id}")
    portal |> form("#actions-send_details") |> render_submit()
    assert has_element?(portal, "#participant-status", "Em reparo")
    p = Repo.get!(Instantflow.Operations.Product, product["id"])

    assert {:ok, %{"ids" => [batch]}} =
             operation.("submit_batch", %{
               "session_id" => session.id,
               "responsible_actor" => "Técnico",
               "lines" => [
                 %{
                   "product_id" => p.id,
                   "product_revision" => p.revision,
                   "quantity" => 2,
                   "note" => ""
                 }
               ]
             })

    {:ok, _} = operation.("handoff", %{"batch_id" => batch})

    {:ok, _} =
      operation.("settle", %{
        "session_id" => session.id,
        "expected_total" => 1000,
        "payment_method" => "cash"
      })

    assert {:ok, %{ticket: %{stage: "collected"}}} = WorkflowRuntime.get(admin, id)

    {:ok, staff, _} =
      live(
        login(build_conn(), admin),
        ~p"/o/horizonte/processos/#{v.workflow_id}/registros/#{id}"
      )

    staff |> form("#release-repair_notice", release: %{recipient: customer.id}) |> render_submit()
    [message] = Delivery.Curated.inbox(customer, v.workflow_id).rows
    {:ok, _} = Delivery.process(1, message.id)
    staff |> element("#refresh-request") |> render_click()
    staff |> element("#retry-curated-#{message.id}") |> render_click()
    assert {:ok, %{status: "succeeded"}} = Delivery.process(1, message.id)
    send(portal.pid, :reconcile)
    assert has_element?(portal, "#participant-messages dd", "Resultado autorizado")

    {:ok, dashboard, _} =
      live(login(build_conn(), admin), ~p"/o/horizonte/processos/#{v.workflow_id}")

    assert has_element?(dashboard, "#open-process-record-#{id}")
  end
end
