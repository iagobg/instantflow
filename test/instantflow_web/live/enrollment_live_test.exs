defmodule InstantflowWeb.EnrollmentLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.EnrollmentFixtures
  import Instantflow.IdentityFixtures, only: [login: 2]
  alias Instantflow.PrivateDocuments

  defp portal_path(f, id),
    do:
      ~p"/o/#{f.parent.organization.slug}/processos/#{f.version.workflow_id}/participacao/family_portal/registros/#{id}"

  test "generated family page uploads quarantined evidence, saves and submits only public fields",
       %{conn: conn} do
    f = enrollment_fixture()
    {:ok, view, _} = live(login(conn, f.parent), portal_path(f, f.enrollment.id))
    assert has_element?(view, "#participant-record")
    refute has_element?(view, "#history")
    refute has_element?(view, "#assignment-form-support")
    refute has_element?(view, "[id='participant-field-placement.assessment']")

    for {key, value} <- Map.drop(parent_values(nil), ["document"]) do
      view
      |> form("[id='participant-field-application.#{key}']", field: %{value: value})
      |> render_submit()
    end

    file =
      file_input(view, "#participant-upload", :document, [
        %{name: "documento.pdf", content: pdf(), type: "application/pdf"}
      ])

    assert render_upload(file, "documento.pdf")
    view |> form("#participant-upload") |> render_submit()
    [doc] = PrivateDocuments.list(f.parent, f.enrollment.id)
    assert has_element?(view, "#participant-documents #documents-#{doc.id}")
    refute has_element?(view, "#participant-download-#{doc.id}")
    view |> form("#actions-submit") |> render_submit()
    refute has_element?(view, "#participant-action-submit")
    assert {:ok, _} = PrivateDocuments.review(f.admin, doc.object_key, true)
    send(view.pid, :reconcile)
    assert has_element?(view, "#participant-download-#{doc.id}")
  end

  test "relationship revocation clears the live page and its editable controls", %{conn: conn} do
    f = enrollment_fixture()
    {:ok, view, _} = live(login(conn, f.parent), portal_path(f, f.enrollment.id))
    assert has_element?(view, "[id='participant-field-application.student_name']")
    assert {:ok, _} = revoke(f)
    assert_redirect(view, "/o/horizonte/processos")
  end

  test "record navigation clears previous values and unrelated identities cannot open the page",
       %{conn: conn} do
    f = enrollment_fixture()
    second = create_record(f.admin, f.version.workflow_id)
    link(f.admin, f.parent, second.id)
    assert {:ok, _} = parent_save(f, %{"student_name" => "Nome do primeiro registro"})
    {:ok, view, _} = live(login(conn, f.parent), portal_path(f, f.enrollment.id))

    assert has_element?(
             view,
             "[id='participant-field-application.student_name'] input[value='Nome do primeiro registro']"
           )

    render_patch(view, portal_path(f, second.id))
    assert_redirect(view, portal_path(f, second.id))
    {:ok, next, _} = live(login(build_conn(), f.parent), portal_path(f, second.id))
    refute has_element?(next, "input[value='Nome do primeiro registro']")
    stranger = Instantflow.IdentityFixtures.staff_fixture("external")

    assert {:error, {:redirect, %{to: "/o/horizonte/processos"}}} =
             live(login(build_conn(), stranger), portal_path(f, f.enrollment.id))
  end

  test "ready direct downloads require current local family authority and private headers", %{
    conn: conn
  } do
    f = enrollment_fixture()
    {:ok, doc} = upload(f.parent, f.enrollment.id, "documento.pdf", pdf())
    target = ~p"/o/horizonte/documentos/#{doc.object_key}"
    assert login(conn, f.parent) |> get(target) |> response(404)
    assert {:ok, _} = PrivateDocuments.review(f.admin, doc.object_key, true)
    download = login(build_conn(), f.parent) |> get(target)
    assert response(download, 200) == pdf()
    assert get_resp_header(download, "cache-control") == ["private, no-store"]
    assert get_resp_header(download, "content-type") == ["application/octet-stream"]
    stranger = Instantflow.IdentityFixtures.staff_fixture("external")
    assert login(build_conn(), stranger) |> get(target) |> response(404)
    b = second_school(f)

    assert login(build_conn(), b.parent)
           |> get(~p"/o/#{b.parent.organization.slug}/documentos/#{doc.object_key}")
           |> response(404)

    assert {:ok, _} = revoke(f)
    assert login(build_conn(), f.parent) |> get(target) |> response(404)
  end
end
