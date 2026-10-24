defmodule InstantflowWeb.CuratedMessagesLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  alias Instantflow.{CuratedFixtures, Delivery, Participants, BuilderFixtures}
  alias Instantflow.WorkflowCatalog.Templates

  test "ambiguous simulated outcome is resolved explicitly through the shared record page", %{
    conn: conn
  } do
    f = CuratedFixtures.fixture("ambiguous")
    {:ok, released} = CuratedFixtures.release(f)
    id = released["message_id"]
    assert {:ok, %{status: "ambiguous"}} = Delivery.process(1, id)

    {:ok, staff, _} =
      live(
        login(conn, f.admin),
        ~p"/o/horizonte/processos/#{f.version.workflow_id}/registros/#{f.id}"
      )

    staff
    |> form("#resolve-#{id}",
      resolution: %{outcome: "succeeded", reason: "Resultado simulado confirmado"}
    )
    |> render_submit()

    refute has_element?(staff, "#resolve-#{id}")
    assert has_element?(staff, "#communication-controls", "succeeded")
    assert {:ok, _} = Instantflow.WorkflowFixtures.transition(f.admin, f.id, "complete")
  end

  test "common release/retry and recipient inbox expose only the curated snapshot", %{conn: conn} do
    f = CuratedFixtures.fixture()

    {:ok, staff, _} =
      live(
        login(conn, f.admin),
        ~p"/o/horizonte/processos/#{f.version.workflow_id}/registros/#{f.id}"
      )

    assert has_element?(staff, "#release-outcome")
    staff |> form("#release-outcome", release: %{recipient: f.recipient.id}) |> render_submit()
    [message] = Instantflow.Delivery.Curated.inbox(f.recipient, f.version.workflow_id).rows
    assert {:ok, _} = Delivery.process(1, message.id)
    staff |> element("#refresh-request") |> render_click()
    staff |> element("#retry-curated-#{message.id}") |> render_click()
    assert {:ok, _} = Delivery.process(1, message.id)

    {:ok, entry, _} =
      live(login(Phoenix.ConnTest.build_conn(), f.recipient), ~p"/o/horizonte/processos")

    assert has_element?(entry, "#inbox-entry-#{f.version.workflow_id}")
    refute has_element?(entry, "#open-process-#{f.version.workflow_id}")

    {:ok, inbox, _} =
      live(
        login(Phoenix.ConnTest.build_conn(), f.recipient),
        ~p"/o/horizonte/processos/#{f.version.workflow_id}/comunicacoes"
      )

    assert has_element?(inbox, "#curated-inbox article dd", "RELEASED-ORIGINAL")
    refute has_element?(inbox, "a[href*='/registros/']")

    assert {:ok, _} =
             Participants.command(
               f.admin,
               BuilderFixtures.participant_command(f.id, f.recipient.id, "revoke", 2)
             )

    send(inbox.pid, :communications_changed)
    refute has_element?(inbox, "#curated-inbox article")
    assert has_element?(inbox, "#message-count", "0 mensagem")
  end

  test "typed communication authoring and synthetic preview publish without live record reads", %{
    conn: conn
  } do
    admin = staff_fixture()
    definition = BuilderFixtures.participant_page_definition()

    {:ok, draft} =
      Templates.import(admin, Instantflow.WorkflowCatalog.Interchange.encode(definition))

    {:ok, editor, _} = live(login(conn, admin), ~p"/o/horizonte/modelos/#{draft.id}")

    editor
    |> form("#template-mappings",
      mapping: %{
        roles: %{requester: ["staff"], reviewer: ["admin"], visitor: ["external"]},
        departments: %{responsible: admin.department_id},
        assignment: "responsible"
      }
    )
    |> render_submit()

    editor
    |> form("#authoring-picker", picker: %{collection: "communications"})
    |> render_submit()

    editor
    |> form("#template-item-form",
      item: %{
        key: "notice",
        label: "Aviso selecionado",
        recipient_relationship: "claimant",
        message_fields: ["request.summary"],
        manager_roles: ["reviewer"],
        department_binding: "responsible",
        behavior: "ambiguous"
      }
    )
    |> render_submit()

    assert has_element?(editor, "#edit-communications-root-notice")

    editor
    |> form("#participant-preview-form",
      preview: %{page: "my_packet", role: "visitor", stage: "draft", verified: "false"}
    )
    |> render_submit()

    assert has_element?(editor, "#participant-preview-result[data-authorized='false']")

    editor
    |> form("#participant-preview-form",
      preview: %{page: "my_packet", role: "visitor", stage: "draft", verified: "true"}
    )
    |> render_submit()

    assert has_element?(editor, "#participant-preview-result[data-authorized='true']")

    assert has_element?(
             editor,
             "[id='preview-field-customer_details.description']",
             "Exemplo sintético"
           )

    refute has_element?(editor, "[id='preview-field-customer_details.private_marker']")
    editor |> element("#publish-template") |> render_click()
    editor |> element("#confirm-publish-template") |> render_click()
    {:ok, saved} = Templates.get(admin, draft.id)
    assert saved.published_version_id
  end
end
