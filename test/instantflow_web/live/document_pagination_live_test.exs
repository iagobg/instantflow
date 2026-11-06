defmodule InstantflowWeb.DocumentPaginationLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  alias Instantflow.{BuilderFixtures, DocumentHistoryFixtures, Participants, WorkflowRuntime}

  test "bounded document navigation preserves drafts and rechecks revocation", %{conn: conn} do
    f = DocumentHistoryFixtures.fixture(103)

    {:ok, view, _} =
      live(
        login(conn, f.visitor),
        "/o/horizonte/processos/#{f.version.workflow_id}/registros/#{f.ticket_id}"
      )

    assert document_count(view) == 50

    view
    |> form("#section-form-customer_details", section: %{description: "Draft survives paging"})
    |> render_change()

    view |> element("#older-private-documents") |> render_click()
    assert document_count(view) == 50
    assert has_element?(view, "#private_documents-#{Enum.at(f.ids, 50)}")
    refute has_element?(view, "#private_documents-#{hd(f.ids)}")
    send(view.pid, :reconcile)
    assert has_element?(view, "#private_documents-#{Enum.at(f.ids, 50)}")
    view |> element("#older-private-documents") |> render_click()
    assert document_count(view) == 3
    refute has_element?(view, "#older-private-documents")
    view |> element("#recent-private-documents") |> render_click()
    assert document_count(view) == 50
    refute has_element?(view, "#recent-private-documents")
    assert has_element?(view, "#section-form-customer_details textarea", "Draft survives paging")
    view |> form("#section-form-customer_details") |> render_submit()
    {:ok, data} = WorkflowRuntime.get(f.visitor, f.ticket_id)

    assert Enum.find(data.sections, &(&1.key == "customer_details")).values["description"] ==
             "Draft survives paging"

    view |> element("#older-private-documents") |> render_click()

    pending =
      file_input(view, "#private-upload-form", :private_document, [
        %{
          name: "pending.pdf",
          content: Instantflow.EnrollmentFixtures.pdf(),
          type: "application/pdf",
          last_modified: 1
        }
      ])

    render_upload(pending, "pending.pdf")

    [channel] =
      :sys.get_state(view.pid).socket.assigns.uploads.private_document.entry_refs_to_pids
      |> Map.values()

    :ok = :sys.suspend(view.pid)

    try do
      {:ok, _} =
        Participants.command(
          f.admin,
          BuilderFixtures.participant_command(f.ticket_id, f.visitor.id, "revoke", 2)
        )

      monitor = Process.monitor(channel)
      GenServer.stop(channel, :normal)
      assert_receive {:DOWN, ^monitor, :process, ^channel, :normal}
    after
      :sys.resume(view.pid)
    end

    assert_redirect(view, "/o/horizonte/solicitacoes", 1_000)
  end

  defp document_count(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#private-documents > article")
    |> Enum.count()
  end
end
