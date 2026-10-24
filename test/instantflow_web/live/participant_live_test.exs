defmodule InstantflowWeb.ParticipantLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  alias Instantflow.{BuilderFixtures, Participants, WorkflowRuntime, PrivateDocuments, Repo}
  alias Instantflow.WorkflowCatalog.{Templates, Interchange}

  test "author, map and publish an independent participant correction page, then operate and revoke it",
       %{conn: conn} do
    admin = staff_fixture()
    clerk = staff_fixture("staff")

    visitor =
      BuilderFixtures.invite_external(admin, "portal-#{Ecto.UUID.generate()}@example.test")

    other = BuilderFixtures.invite_external(admin, "portal-#{Ecto.UUID.generate()}@example.test")

    subject =
      BuilderFixtures.invite_external(admin, "portal-#{Ecto.UUID.generate()}@example.test")

    definition = BuilderFixtures.participant_page_definition()
    source = put_in(definition, ["interface", "pages"], [hd(definition["interface"]["pages"])])
    {:ok, draft} = Templates.import(admin, Interchange.encode(source))
    {:ok, editor, _} = live(login(conn, admin), ~p"/o/horizonte/modelos/#{draft.id}")

    editor
    |> form("#template-mappings",
      mapping: %{
        roles: %{requester: ["staff"], reviewer: ["admin", "teacher"], visitor: ["external"]},
        departments: %{responsible: admin.department_id},
        assignment: "responsible"
      }
    )
    |> render_submit()

    editor |> element("#new-interface-page") |> render_click()
    spec = Enum.at(definition["interface"]["pages"], 1)["participant"]

    editor
    |> form("#interface-page-form",
      interface_page: %{
        key: "my_packet",
        label: "Minha documentação",
        blocks: ["records"],
        participant_enabled: "true",
        participant_visibility: spec["visibility_roles"],
        participant_audience: Enum.map(spec["audience"], &Jason.encode!/1),
        participant_fields: spec["fields"],
        participant_documents: spec["documents"],
        participant_actions: spec["actions"],
        participant_status: "true",
        participant_history: "true",
        access_view: ["requester", "reviewer"]
      }
    )
    |> render_submit()

    refute has_element?(editor, "#publish-template[disabled]")
    editor |> element("#publish-template") |> render_click()
    editor |> element("#confirm-publish-template") |> render_click()
    {:ok, saved} = Templates.get(admin, draft.id)
    version = Repo.get!(Instantflow.WorkflowCatalog.Version, saved.published_version_id)
    assert Enum.at(version.definition["interface"]["pages"], 1)["participant"] == spec

    id = create(clerk, version)
    other_id = create(clerk, version)
    link(admin, visitor, id, "claimant")
    link(admin, other, other_id, "claimant")
    link(admin, subject, id, "observer")

    assert {:ok, _} =
             Instantflow.WorkflowFixtures.transition(
               admin,
               id,
               "request_changes",
               "INTERNAL REASON"
             )

    assert {:ok, _} =
             Instantflow.FinanceFixtures.save(visitor, id, "customer_details", %{
               "private_marker" => "PRIVATE MARKER"
             })

    base = ~p"/o/horizonte/processos/#{version.workflow_id}/participacao/my_packet"

    path =
      ~p"/o/horizonte/processos/#{version.workflow_id}/participacao/my_packet/registros/#{id}"

    {:ok, entry, _} =
      live(login(Phoenix.ConnTest.build_conn(), visitor), ~p"/o/horizonte/processos")

    assert has_element?(entry, "#participant-entry-#{version.workflow_id}-my_packet")
    refute has_element?(entry, "#open-process-#{version.workflow_id}")

    {:ok, subject_entry, _} =
      live(login(Phoenix.ConnTest.build_conn(), subject), ~p"/o/horizonte/processos")

    refute has_element?(subject_entry, "#participant-entry-#{version.workflow_id}-my_packet")
    refute has_element?(subject_entry, "#open-process-#{version.workflow_id}")
    {:ok, list, _} = live(login(Phoenix.ConnTest.build_conn(), visitor), base)
    assert has_element?(list, "#participant-count", "1")
    assert has_element?(list, "#participant-open-#{id}")
    refute has_element?(list, "#participant-open-#{other_id}")

    assert {:error, {:redirect, %{to: "/o/horizonte/processos"}}} =
             live(login(Phoenix.ConnTest.build_conn(), other), path)

    {:ok, portal, _} = live(login(Phoenix.ConnTest.build_conn(), visitor), path)

    assert {:error, {:live_redirect, %{to: ^path}}} =
             live(
               login(Phoenix.ConnTest.build_conn(), visitor),
               ~p"/o/horizonte/processos/#{version.workflow_id}/registros/#{id}"
             )

    parent = staff_fixture("parent")

    {:ok, {_, staff_grant}} =
      Instantflow.Access.grant(admin, parent.id, parent.department_id, "teacher")

    {:ok, parent_portal, _} = live(login(Phoenix.ConnTest.build_conn(), parent), path)
    assert has_element?(parent_portal, "#participant-record")
    refute has_element?(parent_portal, "[id='participant-field-customer_details.description']")
    assert {:ok, _} = Instantflow.Access.revoke(admin, staff_grant.id)
    assert_redirect(parent_portal, "/o/horizonte/processos")
    assert has_element?(portal, "#participant-record")
    refute has_element?(portal, "[id='participant-field-customer_details.private_marker']")
    refute has_element?(portal, "#participant-record", "PRIVATE MARKER")
    refute has_element?(portal, "#participant-history", "INTERNAL REASON")

    portal
    |> form("[id='participant-field-customer_details.description']",
      field: %{value: "Equipamento com defeito"}
    )
    |> render_submit()

    upload =
      file_input(portal, "#participant-upload", :document, [
        %{
          name: "repair.pdf",
          content: Instantflow.EnrollmentFixtures.pdf(),
          type: "application/pdf",
          last_modified: 1
        }
      ])

    render_upload(upload, "repair.pdf")

    portal
    |> form("#participant-upload", upload: %{target: "customer_details.evidence"})
    |> render_submit()

    [doc] = PrivateDocuments.list(visitor, id)
    assert {:ok, _} = PrivateDocuments.review(admin, doc.object_key, true)
    send(portal.pid, :reconcile)
    assert has_element?(portal, "#participant-download-#{doc.id}")
    portal |> form("#actions-send_packet") |> render_submit()
    assert has_element?(portal, "#participant-status", "Em conferência")
    refute has_element?(portal, "[id='participant-field-customer_details.description']")

    assert {:ok, _} =
             Instantflow.WorkflowFixtures.transition(
               admin,
               id,
               "request_changes",
               "Outra correção interna"
             )

    send(portal.pid, :reconcile)
    assert has_element?(portal, "[id='participant-field-customer_details.description']")

    {:ok, clone} = Templates.clone(admin, version.id)

    changed =
      put_in(version.definition, ["interface", "pages"], [
        hd(version.definition["interface"]["pages"])
      ])
      |> rename()

    {:ok, updated} = Templates.save(admin, clone.id, clone.revision, changed, version.bindings)
    assert {:ok, _} = Templates.publish(admin, updated.id, updated.revision)
    {:ok, reconnected, _} = live(login(Phoenix.ConnTest.build_conn(), visitor), path)
    assert has_element?(reconnected, "[id='participant-field-customer_details.description']")
    assert has_element?(reconnected, "#participant-action-send_packet")
    assert has_element?(reconnected, "#participant-status", "Documentação solicitada")

    unknown_path =
      ~p"/o/horizonte/processos/#{version.workflow_id}/participacao/removed_page/registros/#{id}"

    assert {:error, {:live_redirect, %{to: ^path}}} =
             live(login(Phoenix.ConnTest.build_conn(), visitor), unknown_path)

    # A retained draft and a completed-but-unsubmitted upload must be discarded.
    portal
    |> form("[id='participant-field-customer_details.description']",
      field: %{value: "Unsaved private draft"}
    )
    |> render_change()

    pending =
      file_input(portal, "#participant-upload", :document, [
        %{
          name: "pending.pdf",
          content: Instantflow.EnrollmentFixtures.pdf(),
          type: "application/pdf",
          last_modified: 1
        }
      ])

    render_upload(pending, "pending.pdf")

    assert {:ok, _} =
             Participants.command(
               admin,
               BuilderFixtures.participant_command(id, visitor.id, "revoke", 2)
             )

    assert_redirect(portal, "/o/horizonte/processos")
    assert_redirect(reconnected, "/o/horizonte/processos")

    assert {:error, {:redirect, %{to: "/o/horizonte/processos"}}} =
             live(login(Phoenix.ConnTest.build_conn(), visitor), path)

    send(list.pid, :permissions_changed)
    assert has_element?(list, "#participant-count", "0")
    refute has_element?(list, "#participant-open-#{id}")
    assert {:error, :not_found} = PrivateDocuments.download(visitor, doc.object_key)
  end

  defp create(actor, version) do
    {:ok, created} =
      WorkflowRuntime.command(actor, %{
        "operation" => "create",
        "workflow_id" => version.workflow_id,
        "key" => Ecto.UUID.generate()
      })

    created["ticket_id"]
  end

  defp rename(map) when is_map(map), do: Map.new(map, fn {key, value} -> {key, rename(value)} end)
  defp rename(list) when is_list(list), do: Enum.map(list, &rename/1)

  defp rename(value),
    do:
      Map.get(
        %{
          "draft" => "collecting",
          "description" => "response_text",
          "customer_details.description" => "customer_details.response_text",
          "send_packet" => "send_response"
        },
        value,
        value
      )

  defp link(admin, member, id, relationship) do
    for {op, rev} <- [{"create", 0}, {"verify", 1}],
        do:
          {:ok, _} =
            Participants.command(
              admin,
              BuilderFixtures.participant_command(id, member.id, op, rev)
              |> Map.put("relationship", relationship)
            )
  end
end
