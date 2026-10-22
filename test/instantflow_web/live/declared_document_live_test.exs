defmodule InstantflowWeb.DeclaredDocumentLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  alias Instantflow.{BuilderFixtures, Participants, PrivateDocuments, WorkflowRuntime}

  test "generated external upload and independent review clear access on revocation", %{
    conn: conn
  } do
    admin = staff_fixture()
    clerk = staff_fixture("staff")

    visitor =
      BuilderFixtures.invite_external(
        admin,
        "external-doc-#{System.unique_integer([:positive])}@example.test"
      )

    unrelated =
      BuilderFixtures.invite_external(
        admin,
        "external-unrelated-#{System.unique_integer([:positive])}@example.test"
      )

    definition = BuilderFixtures.document_definition()

    bindings = %{
      "roles" => %{"requester" => ["staff"], "reviewer" => ["admin"], "visitor" => ["external"]},
      "departments" => %{"responsible" => admin.department_id}
    }

    version = BuilderFixtures.install(admin, definition, bindings)

    {:ok, result} =
      WorkflowRuntime.command(clerk, %{
        "operation" => "create",
        "workflow_id" => version.workflow_id,
        "key" => Ecto.UUID.generate()
      })

    id = result["ticket_id"]

    path = ~p"/o/horizonte/processos/#{version.workflow_id}/registros/#{id}"
    {:ok, reviewer, _} = live(login(Phoenix.ConnTest.build_conn(), admin), path)
    assert has_element?(reviewer, "#participant-management")

    reviewer
    |> form("#participant-add-claimant", participant: %{membership_id: to_string(visitor.id)})
    |> render_submit()

    [relationship] = Participants.controls(admin, id).relationships
    assert relationship.status == "pending"
    assert {:error, :not_found} = WorkflowRuntime.get(visitor, id)
    reviewer |> element("#participant-verify-#{relationship.id}") |> render_click()
    assert {:error, :not_found} = WorkflowRuntime.get(unrelated, id)
    {:ok, external, _} = live(login(conn, visitor), path)
    assert has_element?(external, "#private-upload-form")
    refute has_element?(external, "#participant-management")
    refute has_element?(reviewer, "#section-form-customer_details")

    upload =
      file_input(external, "#private-upload-form", :private_document, [
        %{
          name: "evidence.pdf",
          content: Instantflow.EnrollmentFixtures.pdf(),
          type: "application/pdf",
          last_modified: 1
        }
      ])

    render_upload(upload, "evidence.pdf")

    external
    |> form("#private-upload-form", upload: %{target: "customer_details.evidence"})
    |> render_submit()

    [doc] = PrivateDocuments.list(visitor, id)
    refute has_element?(external, "#release-private-#{doc.id}")

    external
    |> form("#section-form-customer_details", section: %{description: "Relato sintético"})
    |> render_submit()

    reviewer |> element("#refresh-request") |> render_click()
    assert has_element?(reviewer, "#release-private-#{doc.id}")
    reviewer |> element("#release-private-#{doc.id}") |> render_click()
    external |> element("#refresh-request") |> render_click()
    assert has_element?(external, "#download-private-#{doc.id}")

    reviewer |> element("#participant-revoke-#{relationship.id}") |> render_click()

    assert_redirect(external, "/o/horizonte/solicitacoes")

    denied =
      get(
        login(Phoenix.ConnTest.build_conn(), visitor),
        ~p"/o/horizonte/documentos/#{doc.object_key}"
      )

    assert denied.status == 404
  end
end
