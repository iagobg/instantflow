defmodule Instantflow.EnrollmentTest do
  use Instantflow.DataCase, async: true
  import Instantflow.EnrollmentFixtures

  alias Instantflow.{
    Delivery,
    Identity,
    PrivateDocuments,
    Repo,
    Tenant,
    WorkflowRuntime
  }

  alias Instantflow.Delivery.Message
  import Instantflow.WorkflowFixtures, only: [transition: 3]

  test "complete reference slice with correction, ready-file gate, payment and failed provisioning retry" do
    f = enrollment_fixture()
    id = f.enrollment.ticket_id
    {:ok, doc} = upload(f.parent, f.enrollment.id, "documento.pdf", pdf())
    assert {:ok, _} = parent_save(f, parent_values(doc.object_key))
    assert {:ok, _} = parent_submit(f)

    assert {:ok, _} =
             staff_save(f.admin, id, "identity", %{"display_name" => "Estudante fictício"})

    assert {:error, :attachment_not_ready} = transition(f.admin, id, "verify")
    assert {:ok, _} = PrivateDocuments.review(f.admin, doc.object_key, true)

    assert {:ok, _} =
             Instantflow.WorkflowFixtures.transition(
               f.admin,
               id,
               "correct",
               "Nota interna sigilosa"
             )

    {:ok, current} = WorkflowRuntime.get(f.admin, id)

    assert {:ok, _} =
             Instantflow.Delivery.Curated.release(
               f.admin,
               id,
               "admission_notice",
               f.parent.id,
               current.ticket.revision,
               Ecto.UUID.generate()
             )

    {:ok, public} = portal(f)
    refute inspect(public) =~ "Nota interna sigilosa"
    refute Map.has_key?(public, :events)
    refute Map.has_key?(public, :deliveries)
    refute Map.has_key?(public, :ticket)
    assert {:ok, _} = parent_save(f, parent_values(doc.object_key))
    assert {:ok, _} = parent_submit(f)
    assert {:ok, _} = transition(f.admin, id, "verify")
    {:ok, ticket} = WorkflowRuntime.get(f.members["academic"], id)
    assert ticket.ticket.assigned_department_id == f.departments["academic_department"]
    assert ticket.editable == ["placement"]
    assert Enum.map(ticket.sections, & &1.key) == ["placement"]

    assert {:ok, _} =
             staff_save(f.members["academic"], id, "placement", %{
               "class" => "6A",
               "assessment" => "Avaliação interna confidencial"
             })

    assert {:ok, _} = transition(f.members["academic"], id, "place")
    assert {:ok, _} = staff_save(f.members["finance"], id, "payment", %{"reference" => "SIM-001"})
    assert {:error, :guard_failed} = transition(f.members["finance"], id, "paid")
    Delivery.drain()
    command = Instantflow.WorkflowFixtures.transition_command(f.members["finance"], id, "paid")
    assert {:ok, result} = WorkflowRuntime.command(f.members["finance"], command)
    assert {:ok, ^result} = WorkflowRuntime.command(f.members["finance"], command)
    Delivery.drain()
    {:ok, it} = WorkflowRuntime.get(f.members["it"], id)
    assert it.ticket.stage == "provisioning"
    assert Enum.map(it.sections, & &1.key) == ["identity"]
    assert Enum.any?(WorkflowRuntime.search(f.members["it"]).tickets, &(&1.id == id))
    assert {:error, :guard_failed} = transition(f.members["it"], id, "finish")
    message = Enum.find(it.deliveries, &(&1.kind == "simulate_provisioning"))
    assert message.status == "failed"
    assert {:error, :forbidden} = Delivery.retry(f.parent, message.id)
    assert {:ok, _} = Delivery.retry(f.members["it"], message.id)
    Delivery.drain()
    assert {:ok, _} = transition(f.members["it"], id, "finish")
    {:ok, public} = portal(f)
    assert public.status == "Concluída"
    assert public.actions == []
    assert Enum.all?(public.fields, &(not &1.editable?))

    assert {:ok, 1} =
             Tenant.transaction(f.admin, fn _ ->
               Repo.aggregate(
                 from(m in Message,
                   where: m.ticket_id == ^id and m.kind == "simulate_provisioning"
                 ),
                 :count
               )
             end)
  end

  test "unrelated families cannot discover IDs, counts, files, history or forge mutations" do
    f = enrollment_fixture()
    stranger = Instantflow.IdentityFixtures.staff_fixture("external")
    {:ok, doc} = upload(f.parent, f.enrollment.id, "documento.pdf", pdf())
    assert {:error, :not_found} = portal(f, stranger)
    assert {:error, :forbidden} = upload(stranger, f.enrollment.id, "x.pdf", pdf())
    assert {:error, :not_found} = PrivateDocuments.download(stranger, doc.object_key)
    assert PrivateDocuments.list(stranger, f.enrollment.ticket_id) == []
    assert WorkflowRuntime.search(stranger).total == 0
    assert {:ok, projected} = WorkflowRuntime.get(f.parent, f.enrollment.ticket_id)
    assert Enum.map(projected.sections, & &1.key) == ["application"]

    assert {:error, :forbidden} =
             WorkflowRuntime.command(f.parent, %{
               "operation" => "create",
               "workflow_id" => f.version.workflow_id,
               "key" => Ecto.UUID.generate()
             })

    assert {:error, :forbidden} = PrivateDocuments.review(f.parent, doc.object_key, true)
    assert {:ok, _} = revoke(f)
    assert {:error, :not_found} = portal(f)
    assert {:error, :not_found} = PrivateDocuments.download(f.parent, doc.object_key)

    assert {:error, :forbidden} =
             WorkflowRuntime.command(stranger, %{
               "operation" => "save_section",
               "ticket_id" => f.enrollment.id,
               "section" => "application",
               "values" => parent_values(doc.object_key),
               "expected_stage_revision" => 1,
               "expected_section_revision" => 1,
               "key" => Ecto.UUID.generate()
             })
  end

  test "school-local invitations and files cannot follow a shared login across schools" do
    f = enrollment_fixture()
    b = second_school(f)
    {:ok, doc} = upload(f.parent, f.enrollment.id, "documento.pdf", pdf())
    assert {:error, :not_found} = portal(f, b.parent)
    assert {:error, :not_found} = PrivateDocuments.download(b.parent, doc.object_key)

    {:ok, invitation} =
      Identity.invite(b.admin, %{
        "email" => f.parent.user.email,
        "role" => "external",
        "department_id" => b.admin.department_id
      })

    assert {:error, :proof_required} = Identity.accept_invitation(invitation.token, %{})
    assert {:ok, _} = Identity.accept_invitation(invitation.token, %{}, f.parent.user)
    assert {:error, :not_found} = portal(b, b.parent)
    link(b.admin, b.parent, b.enrollment.id)
    assert {:ok, _} = portal(b, b.parent)
    assert {:error, :invalid_attachment} = parent_save(b, parent_values(doc.object_key))

    assert {:error, :not_found} =
             Instantflow.Participants.command(
               b.admin,
               relationship_command(f.enrollment.id, b.parent.id, "create", 0)
             )
  end

  test "declared participant scope never grants access to an unrelated family or ticket" do
    f = enrollment_fixture()
    other = create_record(f.admin, f.version.workflow_id)

    assert {:error, :not_found} =
             Instantflow.WorkflowRuntime.ParticipantPages.get(
               f.parent,
               f.version.workflow_id,
               "family_portal",
               other.id
             )

    assert {:ok, _} = portal(f)
    assert {:ok, _} = revoke(f)
    assert {:error, :not_found} = portal(f)
  end

  test "unverified and expired invitations grant no access and multiple families need individual verification" do
    f = enrollment_fixture()

    attrs = %{
      "email" => "unverified@example.test",
      "role" => "external",
      "department_id" => f.admin.department_id
    }

    {:ok, invitation} = Identity.invite(f.admin, attrs)

    {:ok, user} =
      Identity.accept_invitation(invitation.token, %{
        "name" => "Pendente",
        "password" => "fictional-password-123"
      })

    parent = Identity.scope(user.id, f.admin.organization_id)
    assert {:error, :not_found} = portal(f, parent)
    assert {:error, :invalid_invitation} = Identity.accept_invitation(invitation.token, %{}, user)

    assert {:ok, _} =
             Instantflow.Participants.command(
               f.admin,
               relationship_command(f.enrollment.id, parent.id, "create", 0)
             )

    assert {:error, :not_found} = portal(f, parent)

    assert {:ok, _} =
             Instantflow.Participants.command(
               f.admin,
               relationship_command(f.enrollment.id, parent.id, "verify", 1)
             )

    assert {:ok, _} = portal(f, parent)
    assert {:ok, _} = revoke(f)
    assert {:ok, _} = portal(f, parent)
    assert {:error, :not_found} = portal(f)
    {:ok, expired} = Identity.invite(f.admin, Map.put(attrs, "email", "expired@example.test"))

    Repo.update!(
      Ecto.Changeset.change(expired.invitation,
        expires_at: DateTime.add(DateTime.utc_now(:second), -1)
      )
    )

    assert {:error, :invalid_invitation} = Identity.accept_invitation(expired.token, %{})
  end

  test "participant invalidations contain no payload and unrelated families receive no event" do
    f = enrollment_fixture()
    Phoenix.PubSub.subscribe(Instantflow.PubSub, WorkflowRuntime.list_topic(f.parent))
    other = create_record(f.admin, f.version.workflow_id)

    {:ok, _} =
      Tenant.raw(f.admin.organization_id, fn ->
        WorkflowRuntime.invalidate_lists(f.admin.organization_id, other.ticket_id)
      end)

    refute_receive :requests_changed

    {:ok, _} =
      Tenant.raw(f.admin.organization_id, fn ->
        WorkflowRuntime.invalidate_lists(f.admin.organization_id, f.enrollment.ticket_id)
      end)

    assert_receive :requests_changed
    refute_receive {:ticket_changed, _, _}
  end
end
