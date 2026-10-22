defmodule Instantflow.DeclaredDocumentPolicyTest do
  use Instantflow.DataCase, async: true
  import Instantflow.IdentityFixtures

  alias Instantflow.{
    BuilderFixtures,
    Participants,
    PrivateDocuments,
    WorkflowRuntime,
    WorkflowFixtures
  }

  alias Instantflow.Access, as: Grants
  alias Instantflow.WorkflowCatalog.{Definition, Interchange}

  setup do
    admin = staff_fixture()
    clerk = staff_fixture("staff")
    reviewer = staff_fixture("staff")
    visitor = staff_fixture("parent")
    unrelated = staff_fixture("parent")
    {:ok, {_, grant}} = Grants.grant(admin, reviewer.id, reviewer.department_id, "admissions")
    reviewer = Instantflow.Identity.scope(reviewer.user_id, reviewer.organization_id)
    definition = BuilderFixtures.document_definition()

    bindings = %{
      "roles" => %{
        "requester" => ["staff"],
        "reviewer" => ["admissions"],
        "visitor" => ["parent"]
      },
      "departments" => %{"responsible" => reviewer.department_id}
    }

    version = BuilderFixtures.install(admin, definition, bindings)

    {:ok, result} =
      WorkflowRuntime.command(clerk, %{
        "operation" => "create",
        "workflow_id" => version.workflow_id,
        "key" => Ecto.UUID.generate()
      })

    id = result["ticket_id"]

    for {operation, revision} <- [{"create", 0}, {"verify", 1}] do
      {:ok, _} =
        Participants.command(
          reviewer,
          BuilderFixtures.participant_command(id, visitor.id, operation, revision)
        )
    end

    %{
      admin: admin,
      clerk: clerk,
      reviewer: reviewer,
      visitor: visitor,
      unrelated: unrelated,
      definition: definition,
      version: version,
      bindings: bindings,
      id: id,
      grant: grant,
      bytes: Instantflow.EnrollmentFixtures.pdf()
    }
  end

  test "renamed fields use declared upload/read/release authority and readiness guards", f do
    assert {:ok, doc} =
             PrivateDocuments.upload(
               f.visitor,
               f.id,
               "customer_details",
               "evidence",
               "sintetico.pdf",
               f.bytes
             )

    assert doc.status == "quarantined"
    assert {:error, :not_found} = PrivateDocuments.download(f.visitor, doc.object_key)
    assert {:error, :forbidden} = PrivateDocuments.review(f.visitor, doc.object_key, true)
    assert {:error, :forbidden} = PrivateDocuments.review(f.admin, doc.object_key, true)
    assert PrivateDocuments.list(f.admin, f.id) == []
    assert PrivateDocuments.list(f.unrelated, f.id) == []
    assert [%{can_review: true}] = PrivateDocuments.list(f.reviewer, f.id)
    assert [%{can_review: false}] = PrivateDocuments.list(f.visitor, f.id)
    assert {:ok, _} = save(f.visitor, f.id, "customer_details", %{"evidence" => doc.object_key})
    assert {:ok, _} = WorkflowFixtures.save(f.clerk, f.id, %{"summary" => "Atendimento"})

    assert {:error, :attachment_not_ready} =
             WorkflowFixtures.transition(f.reviewer, f.id, "complete")

    assert {:ok, ready} = PrivateDocuments.review(f.reviewer, doc.object_key, true)
    assert ready.status == "ready"
    assert {:ok, download} = PrivateDocuments.download(f.visitor, doc.object_key)
    assert download.content == f.bytes
    assert {:ok, _} = WorkflowFixtures.transition(f.reviewer, f.id, "complete")
  end

  test "document receipts replay once and reauthorize current uploader/reviewer authority", f do
    upload_key = Ecto.UUID.generate()

    assert {:ok, doc} =
             PrivateDocuments.upload(
               f.visitor,
               f.id,
               "customer_details",
               "evidence",
               "retry.pdf",
               f.bytes,
               upload_key
             )

    assert {:ok, ^doc} =
             PrivateDocuments.upload(
               f.visitor,
               f.id,
               "customer_details",
               "evidence",
               "retry.pdf",
               f.bytes,
               upload_key
             )

    assert {:error, :idempotency_mismatch} =
             PrivateDocuments.upload(
               f.visitor,
               f.id,
               "customer_details",
               "evidence",
               "retry.pdf",
               f.bytes <> "\n",
               upload_key
             )

    assert length(PrivateDocuments.list(f.visitor, f.id)) == 1
    review_key = Ecto.UUID.generate()
    assert {:ok, ready} = PrivateDocuments.review(f.reviewer, doc.object_key, true, review_key)
    assert {:ok, ^ready} = PrivateDocuments.review(f.reviewer, doc.object_key, true, review_key)
    {:ok, _} = Grants.revoke(f.admin, f.grant.id)

    assert {:error, :forbidden} =
             PrivateDocuments.review(f.reviewer, doc.object_key, true, review_key)

    {:ok, _} = Grants.grant(f.admin, f.reviewer.id, f.reviewer.department_id, "admissions")

    {:ok, _} =
      Participants.command(
        f.reviewer,
        BuilderFixtures.participant_command(f.id, f.visitor.id, "revoke", 2)
      )

    assert {:error, :forbidden} =
             PrivateDocuments.upload(
               f.visitor,
               f.id,
               "customer_details",
               "evidence",
               "retry.pdf",
               f.bytes,
               upload_key
             )
  end

  test "declared size and media limits reject oversized or unapproved synthetic files", f do
    assert {:error, :invalid_file} =
             PrivateDocuments.upload(
               f.visitor,
               f.id,
               "customer_details",
               "evidence",
               "large.pdf",
               "%PDF-" <> String.duplicate("x", 4096) <> "%%EOF"
             )

    png = <<137, 80, 78, 71, 13, 10, 26, 10>> <> String.duplicate("x", 40) <> "IEND"

    assert {:error, :invalid_file} =
             PrivateDocuments.upload(
               f.visitor,
               f.id,
               "customer_details",
               "evidence",
               "image.png",
               png
             )

    assert PrivateDocuments.list(f.visitor, f.id) == []
  end

  test "revocation removes metadata and denies old download links, uploads and reattached values",
       f do
    {:ok, doc} =
      PrivateDocuments.upload(
        f.visitor,
        f.id,
        "customer_details",
        "evidence",
        "sintetico.pdf",
        f.bytes
      )

    {:ok, _} = PrivateDocuments.review(f.reviewer, doc.object_key, true)
    {:ok, data} = WorkflowRuntime.get(f.visitor, f.id)
    section = hd(data.sections)

    stale = %{
      "operation" => "save_section",
      "ticket_id" => f.id,
      "section" => section.key,
      "values" => %{"evidence" => doc.object_key},
      "key" => Ecto.UUID.generate(),
      "expected_stage_revision" => data.ticket.stage_revision,
      "expected_section_revision" => section.revision
    }

    {:ok, _} =
      Participants.command(
        f.reviewer,
        BuilderFixtures.participant_command(f.id, f.visitor.id, "revoke", 2)
      )

    assert PrivateDocuments.list(f.visitor, f.id) == []
    assert {:error, :not_found} = PrivateDocuments.download(f.visitor, doc.object_key)

    assert {:error, :forbidden} =
             PrivateDocuments.upload(
               f.visitor,
               f.id,
               "customer_details",
               "evidence",
               "again.pdf",
               f.bytes
             )

    assert {:error, :forbidden} = WorkflowRuntime.command(f.visitor, stale)
    assert {:ok, _} = PrivateDocuments.download(f.reviewer, doc.object_key)
  end

  test "reviewer grant is revalidated on each release attempt", f do
    {:ok, doc} =
      PrivateDocuments.upload(
        f.visitor,
        f.id,
        "customer_details",
        "evidence",
        "sintetico.pdf",
        f.bytes
      )

    {:ok, _} = Grants.revoke(f.admin, f.grant.id)
    assert {:error, :forbidden} = PrivateDocuments.review(f.reviewer, doc.object_key, true)
    {:ok, _} = Grants.grant(f.admin, f.reviewer.id, f.reviewer.department_id, "admissions")
    assert {:ok, _} = PrivateDocuments.review(f.reviewer, doc.object_key, true)
    assert {:error, :invalid_state} = PrivateDocuments.review(f.reviewer, doc.object_key, true)
  end

  test "attachment claims from another process fail at the file ownership boundary", f do
    {:ok, doc} =
      PrivateDocuments.upload(
        f.visitor,
        f.id,
        "customer_details",
        "evidence",
        "sintetico.pdf",
        f.bytes
      )

    version =
      BuilderFixtures.install(
        f.admin,
        BuilderFixtures.document_definition("other_documents"),
        f.bindings
      )

    {:ok, result} =
      WorkflowRuntime.command(f.clerk, %{
        "operation" => "create",
        "workflow_id" => version.workflow_id,
        "key" => Ecto.UUID.generate()
      })

    id = result["ticket_id"]

    for {operation, revision} <- [{"create", 0}, {"verify", 1}],
        do:
          Participants.command(
            f.reviewer,
            BuilderFixtures.participant_command(id, f.unrelated.id, operation, revision)
          )

    assert {:error, :invalid_attachment} =
             save(f.unrelated, id, "customer_details", %{"evidence" => doc.object_key})

    assert {:error, :not_found} = PrivateDocuments.download(f.unrelated, doc.object_key)
  end

  test "two organizations keep file bytes and attachment claims isolated for shared identities",
       f do
    alias Instantflow.Identity.{Organization, Department, Membership}

    {:ok, original} =
      PrivateDocuments.upload(
        f.visitor,
        f.id,
        "customer_details",
        "evidence",
        "original.pdf",
        f.bytes
      )

    org =
      Repo.insert!(%Organization{
        id: System.unique_integer([:positive]) + 1000,
        slug: "document-other-#{System.unique_integer([:positive])}",
        name: "Outra organização"
      })

    department = Repo.insert!(%Department{organization_id: org.id, name: "Atendimento"})

    for {actor, role} <- [{f.clerk, "admin"}, {f.admin, "staff"}, {f.visitor, "external"}] do
      Repo.insert!(%Membership{
        organization_id: org.id,
        department_id: department.id,
        user_id: actor.user_id,
        role: role
      })
    end

    manager = Instantflow.Identity.scope(f.clerk.user_id, org.id)
    requester = Instantflow.Identity.scope(f.admin.user_id, org.id)
    visitor = Instantflow.Identity.scope(f.visitor.user_id, org.id)

    bindings = %{
      "roles" => %{"requester" => ["staff"], "reviewer" => ["admin"], "visitor" => ["external"]},
      "departments" => %{"responsible" => department.id}
    }

    version = BuilderFixtures.install(manager, BuilderFixtures.document_definition(), bindings)

    {:ok, created} =
      WorkflowRuntime.command(requester, %{
        "operation" => "create",
        "workflow_id" => version.workflow_id,
        "key" => Ecto.UUID.generate()
      })

    id = created["ticket_id"]

    for {operation, revision} <- [{"create", 0}, {"verify", 1}],
        do:
          Participants.command(
            manager,
            BuilderFixtures.participant_command(id, visitor.id, operation, revision)
          )

    {:ok, other} =
      PrivateDocuments.upload(visitor, id, "customer_details", "evidence", "other.pdf", f.bytes)

    {:ok, _} = PrivateDocuments.review(manager, other.object_key, true)
    assert {:ok, _} = PrivateDocuments.download(visitor, other.object_key)
    assert {:error, :not_found} = PrivateDocuments.download(f.visitor, other.object_key)
    assert {:error, :not_found} = PrivateDocuments.download(visitor, original.object_key)

    assert {:error, :invalid_attachment} =
             save(visitor, id, "customer_details", %{"evidence" => original.object_key})

    assert {:error, :invalid_attachment} =
             save(f.visitor, f.id, "customer_details", %{"evidence" => other.object_key})

    assert {:ok, exported} =
             Instantflow.WorkflowCatalog.Templates.export(f.admin, :version, f.version.id)

    assert {:ok, definition} = Interchange.decode(exported.json)
    assert definition == f.definition

    assert {:error, :forbidden} =
             Instantflow.WorkflowCatalog.Templates.export(f.visitor, :version, f.version.id)
  end

  test "portable policies reject missing declarations, broad external reviewers and unknown actor references",
       f do
    assert {:ok, exported} = f.definition |> Interchange.encode() |> Interchange.decode()
    assert :ok = Definition.validate(exported)

    missing =
      update_in(
        f.definition,
        ["sections", Access.at(1), "fields", Access.at(1)],
        &Map.delete(&1, "document_policy")
      )

    assert {:error, errors} = Definition.validate(missing)
    assert Enum.any?(errors, &String.contains?(&1, "document_policy"))

    invalid =
      put_in(
        f.definition,
        ["sections", Access.at(1), "fields", Access.at(1), "document_policy", "reviewers"],
        [%{"role" => "visitor", "scope" => "participant", "relationship" => "claimant"}]
      )

    assert {:error, _} = Definition.validate(invalid)

    invalid =
      put_in(
        f.definition,
        ["sections", Access.at(1), "fields", Access.at(1), "document_policy", "reviewers"],
        [%{"role" => "missing", "scope" => "assigned_department"}]
      )

    assert {:error, _} = Definition.validate(invalid)
  end

  defp save(actor, id, key, values) do
    {:ok, data} = WorkflowRuntime.get(actor, id)
    section = Enum.find(data.sections, &(&1.key == key))

    WorkflowRuntime.command(actor, %{
      "operation" => "save_section",
      "ticket_id" => id,
      "section" => key,
      "values" => values,
      "key" => Ecto.UUID.generate(),
      "expected_stage_revision" => data.ticket.stage_revision,
      "expected_section_revision" => section.revision
    })
  end
end
