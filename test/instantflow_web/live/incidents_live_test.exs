defmodule InstantflowWeb.IncidentsLiveTest do
  use InstantflowWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Instantflow.IncidentFixtures
  alias Instantflow.{Collaboration.Presence, WorkflowRuntime}

  test "restricted triage announces text urgency, filters and hides other reporters", %{
    conn: conn
  } do
    f = incident_fixture()
    id = report(f)

    {:ok, dean, _} =
      live(Instantflow.IdentityFixtures.login(conn, f.dean), ~p"/o/horizonte/ocorrencias")

    assert has_element?(
             dean,
             "#incident-urgency-status[role='status'][aria-live='polite']",
             "1 ocorrência(s)"
           )

    assert has_element?(dean, "#incidents-#{id} strong", "Urgente")
    dean |> form("#incident-filters", filter: %{urgency: "Rotina", stage: ""}) |> render_submit()
    refute has_element?(dean, "#incidents-#{id}")

    {:ok, other, _} =
      live(
        Instantflow.IdentityFixtures.login(conn, f.other_counselor),
        ~p"/o/horizonte/ocorrencias"
      )

    assert has_element?(other, "#incident-count", "0 ocorrência(s)")
    refute has_element?(other, "#incidents-#{id}")
  end

  test "dean and assigned counselor save independent sections; reassign removes protected drafts and presence",
       %{conn: conn} do
    f = incident_fixture()
    id = report(f)
    followup(f, id)
    dean_conn = Instantflow.IdentityFixtures.login(conn, f.dean)
    counselor_conn = Instantflow.IdentityFixtures.login(conn, f.counselor)
    {:ok, dean, _} = live(dean_conn, ~p"/o/horizonte/solicitacoes/#{id}")
    {:ok, counselor, _} = live(counselor_conn, ~p"/o/horizonte/solicitacoes/#{id}")
    refute has_element?(dean, "#section-form-support")
    refute has_element?(counselor, "#section-form-discipline")

    counselor
    |> form("#section-form-support", section: %{notes: "PRIVADO_RASCUNHO"})
    |> render_change()

    dean
    |> form("#section-form-discipline",
      section: %{triage: "Triagem", actions: "Ação independente", resolution: "Resolução"}
    )
    |> render_submit()

    counselor
    |> form("#section-form-support", section: %{notes: "PRIVADO_SALVO"})
    |> render_submit()

    assert has_element?(counselor, "#section-form-support textarea", "PRIVADO_SALVO")
    refute has_element?(dean, "#sections", "PRIVADO_SALVO")
    {:ok, dean_data} = WorkflowRuntime.get(f.dean, id)
    assert Presence.editors(f.dean, dean_data) == []

    counselor
    |> form("#section-form-support", section: %{notes: "PRIVADO_RASCUNHO"})
    |> render_change()

    # Refresh and acknowledge before issuing a revision-sensitive assignment.
    dean |> element("#refresh-request") |> render_click()

    if has_element?(dean, "#review-request"),
      do: dean |> element("#review-request") |> render_click()

    dean
    |> form("#assignment-form-support",
      assignment: %{membership_id: "", reason: "Revogar acesso local"}
    )
    |> render_submit()

    assert_redirect(counselor, "/o/horizonte/solicitacoes")
    assert {:error, :not_found} = WorkflowRuntime.get(f.counselor, id)
  end

  test "counselor upload stays confined and supports quarantine/release", %{conn: conn} do
    f = incident_fixture()
    id = report(f)
    followup(f, id)

    {:ok, view, _} =
      live(
        Instantflow.IdentityFixtures.login(conn, f.counselor),
        ~p"/o/horizonte/solicitacoes/#{id}"
      )

    upload =
      file_input(view, "#private-upload-form", :private_document, [
        %{name: "ficticio.pdf", content: "%PDF-1.4\nFICTICIO\n%%EOF", type: "application/pdf"}
      ])

    render_upload(upload, "ficticio.pdf")

    view
    |> form("#private-upload-form", upload: %{target: "support.attachment"})
    |> render_submit()

    assert has_element?(view, "#private-documents", "Em quarentena")
    [doc] = Instantflow.PrivateDocuments.list(f.counselor, id)
    view |> element("#release-private-#{doc.id}") |> render_click()
    assert has_element?(view, "#download-private-#{doc.id}")
    view |> form("#section-form-support", section: %{notes: "Nota privada"}) |> render_submit()
    {:ok, data} = WorkflowRuntime.get(f.counselor, id)
    assert Enum.find(data.sections, &(&1.key == "support")).values["attachment"] == doc.object_key
    assert Instantflow.PrivateDocuments.list(f.teacher, id) == []
  end
end
