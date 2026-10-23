defmodule InstantflowWeb.Sprint11ParticipantReleaseMatrixTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures

  alias Instantflow.{
    Access,
    BuilderFixtures,
    Delivery,
    Identity,
    Participants,
    PrivateDocuments,
    Repo,
    WorkflowRuntime
  }

  alias Instantflow.WorkflowCatalog.Templates
  alias Instantflow.WorkflowRuntime.{ParticipantPages, Projections, Receipt}

  test "any admitted pinned page can release its exact document; page admission never releases another section" do
    f = fixture()
    selected = document(f, "customer_details", "evidence", f.visitor)
    omitted = document(f, "customer_details", "omitted", f.visitor)
    gated = document(f, "customer_details", "gated", f.visitor)
    confidential = document(f, "internal", "proof", f.reviewer)

    {:ok, first} = ParticipantPages.get(f.visitor, f.version.workflow_id, "my_packet", f.id)
    assert first.documents == []
    {:ok, editor, _} = live(login(build_conn(), f.visitor), page_path(f, "my_packet"))

    editor
    |> form("[id='participant-field-customer_details.description']",
      field: %{value: "Released participant summary"}
    )
    |> render_submit()

    assert Enum.map(first.fields, & &1.ref) == ["customer_details.description"]
    {:ok, files} = ParticipantPages.get(f.visitor, f.version.workflow_id, "files", f.id)
    assert Enum.map(files.documents, & &1.object_key) == [selected.object_key]
    assert files.fields == []
    assert download(f.visitor, selected).status == 200
    assert {:ok, %{content: bytes}} = PrivateDocuments.download(f.visitor, selected.object_key)
    assert bytes == Instantflow.EnrollmentFixtures.pdf()

    for doc <- [omitted, gated, confidential] do
      assert {:error, :not_found} = PrivateDocuments.download(f.visitor, doc.object_key)
      assert download(f.visitor, doc).status == 404
    end

    {:ok, empty} = ParticipantPages.get(f.visitor, f.version.workflow_id, "confidential", f.id)
    assert empty.fields == [] and empty.documents == [] and empty.uploads == []

    assert {:error, :not_found} =
             ParticipantPages.get(f.visitor, f.version.workflow_id, "gated", f.id)

    assert Projections.participant_search(f.visitor, f.version.workflow_id, "gated").total == 0
    assert Projections.participant_search(f.visitor, f.version.workflow_id, "files").total == 1
    refute Enum.any?(Projections.participant_options(f.visitor), &(&1.key == "gated"))

    {:ok, page, _} = live(login(build_conn(), f.visitor), page_path(f, "files"))
    assert has_element?(page, "#participant-download-#{selected.id}")

    for doc <- [omitted, gated, confidential],
        do: refute(has_element?(page, "#participant-download-#{doc.id}"))

    refute has_element?(page, "[id='participant-field-internal.secret']")
    before_docs = Repo.aggregate(Instantflow.Enrollment.Document, :count)
    before_receipts = Repo.aggregate(Receipt, :count)

    upload =
      file_input(page, "#participant-upload", :document, [
        %{
          name: "forged.pdf",
          content: Instantflow.EnrollmentFixtures.pdf(),
          type: "application/pdf"
        }
      ])

    render_upload(upload, "forged.pdf")

    page
    |> form("#participant-upload")
    |> render_submit(%{"upload" => %{"target" => "customer_details.omitted"}})

    assert has_element?(page, "#flash-error")
    assert Repo.aggregate(Instantflow.Enrollment.Document, :count) == before_docs
    assert Repo.aggregate(Receipt, :count) == before_receipts

    {:ok, {_, grant}} = Access.grant(f.admin, f.visitor.id, f.visitor.department_id, "head")
    {:ok, gated_page, _} = live(login(build_conn(), f.visitor), page_path(f, "gated"))
    assert has_element?(gated_page, "#participant-download-#{gated.id}")
    assert download(f.visitor, gated).status == 200
    {:ok, current} = WorkflowRuntime.get(f.admin, f.id)

    {:ok, released} =
      Delivery.Curated.release(
        f.admin,
        f.id,
        "summary_notice",
        f.visitor.id,
        current.ticket.revision,
        Ecto.UUID.generate()
      )

    {:ok, _} = Access.revoke(f.admin, grant.id)
    assert_redirect(gated_page, "/o/horizonte/processos")
    assert download(f.visitor, gated).status == 404
    assert download(f.visitor, selected).status == 200
    # Recipient eligibility belongs to the verified relationship, independently
    # of losing a page-only role; delivery still rechecks the releasing author.
    assert {:ok, %{status: "succeeded"}} =
             Delivery.process(f.admin.organization_id, released["message_id"])

    [message] = Delivery.Curated.inbox(f.visitor, f.version.workflow_id).rows
    assert message.content == [%{"label" => "Relato", "value" => "Released participant summary"}]

    assert {:ok, underlying} = WorkflowRuntime.get(f.visitor, f.id)
    assert Enum.any?(underlying.sections, &(&1.key == "customer_details"))

    # Re-publication changes admission for new records; it cannot replace the old pin.
    {:ok, draft} = Templates.clone(f.admin, f.version.id)

    changed =
      put_in(draft.definition, ["interface", "pages"], [
        hd(draft.definition["interface"]["pages"]),
        draft.definition["interface"]["pages"]
        |> Enum.find(&(&1["key"] == "files"))
        |> put_in(["participant", "visibility_roles"], ["reviewer"])
      ])

    {:ok, draft} = Templates.save(f.admin, draft.id, draft.revision, changed, f.bindings)
    {:ok, latest} = Templates.publish(f.admin, draft.id, draft.revision)
    assert {:ok, _} = ParticipantPages.get(f.visitor, f.version.workflow_id, "files", f.id)
    assert download(f.visitor, selected).status == 200
    newer_id = create(f.clerk, latest)
    link(f.admin, f.visitor, newer_id, "claimant")

    {:ok, _} =
      Instantflow.WorkflowFixtures.transition(
        f.admin,
        newer_id,
        "request_changes",
        "Nova correção"
      )

    newer = document(%{f | id: newer_id}, "customer_details", "evidence", f.visitor)
    assert download(f.visitor, newer).status == 404

    assert {:error, :not_found} =
             ParticipantPages.get(f.visitor, latest.workflow_id, "files", newer_id)

    assert Projections.participant_search(f.visitor, latest.workflow_id, "files").total == 1

    assert Enum.map(
             Projections.participant_search(f.visitor, latest.workflow_id, "files").rows,
             & &1.id
           ) == [f.id]

    {:ok, _} =
      Participants.command(
        f.admin,
        BuilderFixtures.participant_command(f.id, f.visitor.id, "revoke", 2)
      )

    assert_redirect(page, "/o/horizonte/processos")
    assert download(f.visitor, selected).status == 404
    assert Projections.participant_search(f.visitor, latest.workflow_id, "files").total == 0
    assert Projections.participant_options(f.visitor) == []
    assert Delivery.Curated.inbox(f.visitor, f.version.workflow_id).rows == []

    assert {:error, :not_found} =
             ParticipantPages.upload(
               f.visitor,
               latest.workflow_id,
               "files",
               f.id,
               "customer_details.evidence",
               "retry.pdf",
               Instantflow.EnrollmentFixtures.pdf(),
               Ecto.UUID.generate()
             )
  end

  test "subject-only, unrelated, cross-process and cross-tenant identities cannot use discovered file IDs; explicit scoped staff grants reauthorize" do
    f = fixture()
    selected = document(f, "customer_details", "evidence", f.visitor)

    other =
      BuilderFixtures.invite_external(f.admin, "unrelated-#{Ecto.UUID.generate()}@example.test")

    subject =
      BuilderFixtures.invite_external(f.admin, "subject-#{Ecto.UUID.generate()}@example.test")

    link(f.admin, subject, f.id, "observer")
    {:ok, _} = Access.grant(f.admin, subject.id, subject.department_id, "head")

    for actor <- [other, subject] do
      assert Projections.participant_options(actor) == []

      for key <- ~w(my_packet files gated confidential) do
        assert Projections.participant_search(actor, f.version.workflow_id, key).total == 0

        assert {:error, :not_found} =
                 ParticipantPages.get(actor, f.version.workflow_id, key, f.id)

        assert {:error, :not_found} =
                 ParticipantPages.upload(
                   actor,
                   f.version.workflow_id,
                   key,
                   f.id,
                   "customer_details.evidence",
                   "forged.pdf",
                   Instantflow.EnrollmentFixtures.pdf(),
                   Ecto.UUID.generate()
                 )
      end

      assert {:error, :not_found} = PrivateDocuments.download(actor, selected.object_key)
      assert download(actor, selected).status == 404
    end

    parent = staff_fixture("parent")
    assert download(parent, selected).status == 404
    {:ok, {_, grant}} = Access.grant(f.admin, parent.id, parent.department_id, "teacher")
    assert download(parent, selected).status == 200
    assert {:ok, data} = ParticipantPages.get(parent, f.version.workflow_id, "files", f.id)
    assert Enum.map(data.documents, & &1.object_key) == [selected.object_key]
    {:ok, _} = Access.revoke(f.admin, grant.id)
    assert download(parent, selected).status == 404

    assert {:error, :not_found} =
             ParticipantPages.get(parent, f.version.workflow_id, "files", f.id)

    other_process =
      BuilderFixtures.install(
        f.admin,
        Map.put(f.definition, "template_key", "second_release_process"),
        f.bindings
      )

    assert {:error, :not_found} =
             ParticipantPages.get(f.visitor, other_process.workflow_id, "files", f.id)

    assert Projections.participant_search(f.visitor, other_process.workflow_id, "files").total ==
             0

    foreign_scope = second_organization(f.visitor)
    assert {:error, :not_found} = PrivateDocuments.download(foreign_scope, selected.object_key)
    assert download(foreign_scope, selected).status == 404

    assert {:error, :not_found} =
             ParticipantPages.get(foreign_scope, f.version.workflow_id, "files", f.id)

    assert Projections.participant_search(foreign_scope, f.version.workflow_id, "files").total ==
             0
  end

  defp fixture do
    admin = staff_fixture()
    clerk = staff_fixture("staff")
    reviewer = staff_fixture("staff")
    {:ok, _} = Access.grant(admin, reviewer.id, reviewer.department_id, "teacher")

    visitor =
      BuilderFixtures.invite_external(admin, "release-#{Ecto.UUID.generate()}@example.test")

    d = BuilderFixtures.participant_page_definition()
    evidence = Instantflow.WorkflowCatalog.Definition.fields(d)["customer_details.evidence"]
    first = Enum.at(d["interface"]["pages"], 1) |> put_in(["participant", "documents"], [])

    files =
      first
      |> Map.put("key", "files")
      |> Map.put("label", "Arquivos selecionados")
      |> put_in(["participant", "fields"], [])
      |> put_in(["participant", "documents"], ["customer_details.evidence"])

    gated =
      files
      |> Map.put("key", "gated")
      |> put_in(["participant", "visibility_roles"], ["page_reader"])
      |> put_in(["participant", "documents"], ["customer_details.gated"])

    confidential =
      files
      |> Map.put("key", "confidential")
      |> put_in(["participant", "fields"], ["internal.secret"])
      |> put_in(["participant", "documents"], ["internal.proof"])

    internal = %{
      "key" => "internal",
      "label" => "Dados internos",
      "classification" => "restricted",
      "access" => [
        %{
          "role" => "reviewer",
          "scope" => "workflow_department",
          "department_binding" => "responsible",
          "read" => true,
          "edit_stages" => ["draft"]
        }
      ],
      "fields" => [
        %{"key" => "secret", "label" => "Segredo", "type" => "short_text"},
        Map.put(evidence, "key", "proof")
      ]
    }

    definition =
      d
      |> Map.put("template_key", "multiple_release_pages")
      |> Map.update!("capabilities", &(&1 ++ ["communications"]))
      |> Map.put("communications", [
        %{
          "key" => "summary_notice",
          "label" => "Resumo liberado",
          "recipient_relationship" => "claimant",
          "fields" => ["customer_details.description"],
          "behavior" => "success",
          "release_actors" => [
            %{
              "role" => "reviewer",
              "scope" => "workflow_department",
              "department_binding" => "responsible"
            }
          ]
        }
      ])
      |> Map.update!(
        "role_requirements",
        &(&1 ++ [%{"key" => "page_reader", "label" => "Leitor da página"}])
      )
      |> update_in(
        ["sections", Elixir.Access.at(1), "fields"],
        &(&1 ++ [Map.put(evidence, "key", "omitted"), Map.put(evidence, "key", "gated")])
      )
      |> Map.update!("sections", &(&1 ++ [internal]))
      |> put_in(["interface", "pages"], [
        hd(d["interface"]["pages"]),
        first,
        files,
        gated,
        confidential
      ])

    bindings = %{
      "roles" => %{
        "requester" => ["staff"],
        "reviewer" => ["admin", "teacher"],
        "visitor" => ["external"],
        "page_reader" => ["head"]
      },
      "departments" => %{"responsible" => admin.department_id}
    }

    version = BuilderFixtures.install(admin, definition, bindings)
    id = create(clerk, version)
    link(admin, visitor, id, "claimant")

    {:ok, _} =
      Instantflow.WorkflowFixtures.transition(admin, id, "request_changes", "Correção sintética")

    %{
      admin: admin,
      clerk: clerk,
      reviewer: reviewer,
      visitor: visitor,
      version: version,
      id: id,
      definition: definition,
      bindings: bindings
    }
  end

  defp create(actor, version) do
    {:ok, result} =
      WorkflowRuntime.command(actor, %{
        "operation" => "create",
        "workflow_id" => version.workflow_id,
        "key" => Ecto.UUID.generate()
      })

    result["ticket_id"]
  end

  defp link(admin, actor, id, relationship) do
    for {operation, revision} <- [{"create", 0}, {"verify", 1}] do
      {:ok, _} =
        Participants.command(
          admin,
          BuilderFixtures.participant_command(id, actor.id, operation, revision)
          |> Map.put("relationship", relationship)
        )
    end
  end

  defp document(f, section, field, uploader) do
    {:ok, doc} =
      PrivateDocuments.upload(
        uploader,
        f.id,
        section,
        field,
        field <> ".pdf",
        Instantflow.EnrollmentFixtures.pdf()
      )

    {:ok, _} = PrivateDocuments.review(f.admin, doc.object_key, true)
    doc
  end

  defp download(actor, doc),
    do:
      get(
        login(build_conn(), actor),
        "/o/#{actor.organization.slug}/documentos/#{doc.object_key}"
      )

  defp page_path(f, key),
    do: "/o/horizonte/processos/#{f.version.workflow_id}/participacao/#{key}/registros/#{f.id}"

  # Organization/membership rows establish the low-level isolation fixture only;
  # all workflows, relationships and documents use supported context commands.
  defp second_organization(actor) do
    org =
      Repo.insert!(%Instantflow.Identity.Organization{
        slug: "foreign-#{Ecto.UUID.generate()}",
        name: "Outra organização"
      })

    dept =
      Repo.insert!(%Instantflow.Identity.Department{organization_id: org.id, name: "Atendimento"})

    Repo.insert!(%Instantflow.Identity.Membership{
      organization_id: org.id,
      user_id: actor.user_id,
      department_id: dept.id,
      role: "external"
    })

    Identity.scope(actor.user_id, org.id)
  end
end
