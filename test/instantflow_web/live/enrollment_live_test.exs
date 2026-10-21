defmodule InstantflowWeb.EnrollmentLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.EnrollmentFixtures
  import Instantflow.IdentityFixtures, only: [login: 2]
  alias Instantflow.{Enrollment, PrivateDocuments}

  test "parent portal uploads a quarantined document, saves, submits and exposes only public controls",
       %{conn: conn} do
    f = enrollment_fixture()
    {:ok, view, _} = live(login(conn, f.parent), "/o/horizonte/matriculas/#{f.enrollment.id}")
    assert has_element?(view, "#enrollment-form")
    refute has_element?(view, "#internal-enrollment")
    refute has_element?(view, "#guardian-invitation-form")
    refute has_element?(view, "#history")

    upload =
      file_input(view, "#document-upload-form", :document, [
        %{name: "documento.pdf", content: pdf(), type: "application/pdf"}
      ])

    assert render_upload(upload, "documento.pdf")
    view |> form("#document-upload-form") |> render_submit()
    [doc] = Enrollment.documents(f.parent, f.enrollment.id)
    assert has_element?(view, "#enrollment-documents article", "documento.pdf")
    refute has_element?(view, "#download-#{doc.id}")
    params = parent_values(doc.object_key)
    view |> form("#enrollment-form", application: params) |> render_change()
    assert has_element?(view, "#enrollment-unsaved")
    view |> form("#enrollment-form", application: params) |> render_submit()
    refute has_element?(view, "#enrollment-unsaved")
    view |> element("#submit-enrollment") |> render_click()
    assert has_element?(view, "#enrollment-status", "Documentos em verificação")
    refute has_element?(view, "#submit-enrollment")
    assert {:ok, _} = PrivateDocuments.review(f.admin, doc.object_key, true)
    send(view.pid, :enrollments_changed)
    assert has_element?(view, "#download-#{doc.id}")
  end

  test "guardian revocation clears the live form and draft", %{conn: conn} do
    f = enrollment_fixture()
    {:ok, view, _} = live(login(conn, f.parent), "/o/horizonte/matriculas/#{f.enrollment.id}")

    view
    |> form("#enrollment-form", application: %{student_name: "Rascunho privado"})
    |> render_change()

    assert has_element?(view, "#enrollment-unsaved")
    assert {:ok, _} = Enrollment.verify(f.admin, f.link.id, false)
    assert_redirect(view, "/o/horizonte/matriculas")
  end

  test "a route change clears the previous child's draft and cross-family IDs redirect", %{
    conn: conn
  } do
    f = enrollment_fixture()
    {:ok, second} = Enrollment.create(f.admin, f.version.workflow_id, Ecto.UUID.generate())
    {:ok, invitation} = Enrollment.invite(f.admin, second.id, f.parent.user.email)
    {:ok, _} = Instantflow.Identity.accept_invitation(invitation.token, %{}, f.parent.user)
    [link] = Enrollment.guardians(f.admin, second.id)
    {:ok, _} = Enrollment.verify(f.admin, link.id, true)
    {:ok, view, _} = live(login(conn, f.parent), "/o/horizonte/matriculas/#{f.enrollment.id}")

    view
    |> form("#enrollment-form", application: %{student_name: "Rascunho anterior"})
    |> render_change()

    render_patch(view, "/o/horizonte/matriculas/#{second.id}")
    refute has_element?(view, "#enrollment-unsaved")

    assert has_element?(view, "#enrollment-form")
    assert has_element?(view, "#application_student_name:not([value])")
    stranger = Instantflow.IdentityFixtures.staff_fixture("parent")

    assert {:error, {:redirect, %{to: "/o/horizonte/matriculas"}}} =
             live(login(build_conn(), stranger), "/o/horizonte/matriculas/#{f.enrollment.id}")
  end

  test "staff portal invites, verifies and publishes only an explicit message", %{conn: conn} do
    f = enrollment_fixture()
    {:ok, view, _} = live(login(conn, f.admin), "/o/horizonte/matriculas/#{f.enrollment.id}")
    assert has_element?(view, "#internal-enrollment")
    assert has_element?(view, "#verify-guardian-#{f.link.id}")

    view
    |> form("#parent-message-form", message: %{text: "Confira os documentos fictícios."})
    |> render_submit()

    {:ok, data} = Enrollment.get(f.parent, f.enrollment.id)
    assert data.public_message == "Confira os documentos fictícios."

    view
    |> form("#guardian-invitation-form", invitation: %{email: "second@example.test"})
    |> render_submit()

    assert has_element?(view, "#guardian-invitation-token")
  end

  test "ready downloads require the same verified local family and return private headers", %{
    conn: conn
  } do
    f = enrollment_fixture()
    {:ok, doc} = Enrollment.upload(f.parent, f.enrollment.id, "documento.pdf", pdf())
    path = "/o/horizonte/documentos/#{doc.object_key}"
    assert login(conn, f.parent) |> get(path) |> response(404)
    {:ok, _} = PrivateDocuments.review(f.admin, doc.object_key, true)
    download = login(build_conn(), f.parent) |> get(path)
    assert response(download, 200) == pdf()
    assert get_resp_header(download, "cache-control") == ["private, no-store"]
    assert get_resp_header(download, "content-type") == ["application/octet-stream"]
    stranger = Instantflow.IdentityFixtures.staff_fixture("parent")
    assert login(build_conn(), stranger) |> get(path) |> response(404)
    b = second_school(f)

    assert login(build_conn(), b.parent)
           |> get("/o/#{b.parent.organization.slug}/documentos/#{doc.object_key}")
           |> response(404)
  end
end
