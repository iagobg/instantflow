defmodule Instantflow.EnrollmentTest do
  use Instantflow.DataCase, async: true
  import Instantflow.EnrollmentFixtures

  alias Instantflow.{
    Delivery,
    Enrollment,
    Identity,
    PrivateDocuments,
    Repo,
    Tenant,
    WorkflowRuntime
  }

  alias Instantflow.Enrollment.GuardianLink
  alias Instantflow.Delivery.Message
  import Instantflow.WorkflowFixtures, only: [transition: 3]

  test "complete reference slice with correction, ready-file gate, payment and failed provisioning retry" do
    f = enrollment_fixture()
    id = f.enrollment.ticket_id
    {:ok, doc} = Enrollment.upload(f.parent, f.enrollment.id, "documento.pdf", pdf())
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

    assert {:ok, _} =
             Enrollment.public_message(f.admin, f.enrollment.id, "Confira o nome e reenvie.")

    {:ok, public} = Enrollment.get(f.parent, f.enrollment.id)
    assert public.public_message == "Confira o nome e reenvie."
    refute Map.has_key?(public, :events)
    refute Map.has_key?(public, :deliveries)
    refute public.ticket_id
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
    assert Enum.any?(WorkflowRuntime.list(f.members["it"]), &(&1.id == id))
    assert {:error, :guard_failed} = transition(f.members["it"], id, "finish")
    message = Enum.find(it.deliveries, &(&1.kind == "simulate_provisioning"))
    assert message.status == "failed"
    assert {:error, :forbidden} = Delivery.retry(f.parent, message.id)
    assert {:ok, _} = Delivery.retry(f.members["it"], message.id)
    Delivery.drain()
    assert {:ok, _} = transition(f.members["it"], id, "finish")
    {:ok, public} = Enrollment.get(f.parent, f.enrollment.id)
    assert public.status == "Matrícula concluída"
    refute public.editable

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
    stranger = Instantflow.IdentityFixtures.staff_fixture("parent")
    {:ok, doc} = Enrollment.upload(f.parent, f.enrollment.id, "documento.pdf", pdf())
    assert Enrollment.list(stranger) == []
    assert {:error, :not_found} = Enrollment.get(stranger, f.enrollment.id)
    assert {:error, :not_found} = Enrollment.upload(stranger, f.enrollment.id, "x.pdf", pdf())
    assert {:error, :not_found} = PrivateDocuments.download(stranger, doc.object_key)
    assert PrivateDocuments.list(stranger, f.enrollment.ticket_id) == []
    assert WorkflowRuntime.search(stranger).total == 0
    assert {:error, :not_found} = WorkflowRuntime.get(f.parent, f.enrollment.ticket_id)

    assert {:error, :not_found} =
             Enrollment.save(
               stranger,
               f.enrollment.id,
               parent_values(doc.object_key),
               1,
               1,
               Ecto.UUID.generate()
             )

    assert {:error, :forbidden} =
             WorkflowRuntime.command(f.parent, %{
               "operation" => "create",
               "workflow_id" => f.version.workflow_id,
               "key" => Ecto.UUID.generate()
             })

    assert {:error, :forbidden} = PrivateDocuments.review(f.parent, doc.object_key, true)
    assert {:ok, _} = Enrollment.verify(f.admin, f.link.id, false)
    assert Enrollment.list(f.parent) == []
    assert {:error, :not_found} = Enrollment.get(f.parent, f.enrollment.id)
    assert {:error, :not_found} = PrivateDocuments.download(f.parent, doc.object_key)
  end

  test "school-local links, invitations and files cannot follow a shared login across schools" do
    f = enrollment_fixture()
    b = second_school(f)
    {:ok, doc} = Enrollment.upload(f.parent, f.enrollment.id, "documento.pdf", pdf())
    assert Enrollment.list(b.parent) == []
    assert {:error, :not_found} = Enrollment.get(b.parent, f.enrollment.id)
    assert {:error, :not_found} = PrivateDocuments.download(b.parent, doc.object_key)

    assert {:error, :forbidden} =
             Identity.invite(b.admin, %{
               "email" => f.parent.user.email,
               "role" => "parent",
               "department_id" => b.admin.department_id,
               "enrollment_id" => f.enrollment.id
             })

    {:ok, invitation} = Enrollment.invite(b.admin, b.enrollment.id, f.parent.user.email)
    assert {:error, :proof_required} = Identity.accept_invitation(invitation.token, %{})
    assert {:ok, _} = Identity.accept_invitation(invitation.token, %{}, f.parent.user)
    assert Enrollment.list(b.parent) == []
    link = Repo.get_by!(GuardianLink, enrollment_id: b.enrollment.id, membership_id: b.parent.id)
    assert {:ok, _} = Enrollment.verify(b.admin, link.id, true)
    assert length(Enrollment.list(b.parent)) == 1

    assert {:error, :invalid_attachment} =
             Enrollment.save(
               b.parent,
               b.enrollment.id,
               parent_values(doc.object_key),
               1,
               1,
               Ecto.UUID.generate()
             )

    assert {:error, :not_found} = Enrollment.invite(b.admin, f.enrollment.id, "x@example.test")
  end

  test "template department scopes never grant a parent access to an unrelated family" do
    f = enrollment_fixture()
    {:ok, other} = Enrollment.create(f.admin, f.version.workflow_id, Ecto.UUID.generate())

    assert {:ok, false} =
             Tenant.transaction(f.parent, fn actor ->
               ticket = Repo.get!(Instantflow.WorkflowRuntime.Ticket, other.ticket_id)

               section = %{
                 "access" => [
                   %{
                     "role" => "guardian",
                     "scope" => "assigned_department",
                     "read" => true,
                     "edit_stages" => ["draft"]
                   }
                 ]
               }

               Instantflow.WorkflowRuntime.Policy.section?(
                 actor,
                 ticket,
                 f.version,
                 section,
                 :read
               )
             end)

    assert {:ok, true} =
             Tenant.transaction(f.parent, fn actor ->
               ticket = Repo.get!(Instantflow.WorkflowRuntime.Ticket, f.enrollment.ticket_id)

               section = %{
                 "access" => [
                   %{
                     "role" => "guardian",
                     "scope" => "guardian",
                     "read" => true,
                     "edit_stages" => ["draft"]
                   }
                 ]
               }

               Instantflow.WorkflowRuntime.Policy.section?(
                 actor,
                 ticket,
                 f.version,
                 section,
                 :read
               )
             end)
  end

  test "unverified and expired invitations grant no access and multiple local guardians need individual verification" do
    f = enrollment_fixture()
    {:ok, invitation} = Enrollment.invite(f.admin, f.enrollment.id, "unverified@example.test")

    {:ok, user} =
      Identity.accept_invitation(invitation.token, %{
        "name" => "Responsável pendente",
        "password" => "fictional-password-123"
      })

    parent = Identity.scope(user.id, f.admin.organization_id)
    assert Enrollment.list(parent) == []
    assert {:error, :not_found} = Enrollment.get(parent, f.enrollment.id)
    assert {:error, :invalid_invitation} = Identity.accept_invitation(invitation.token, %{}, user)
    link = Repo.get_by!(GuardianLink, enrollment_id: f.enrollment.id, membership_id: parent.id)
    {:ok, _} = Enrollment.verify(f.admin, link.id, true)
    assert length(Enrollment.list(parent)) == 1
    {:ok, _} = Enrollment.verify(f.admin, f.link.id, false)
    assert length(Enrollment.list(parent)) == 1
    assert Enrollment.list(f.parent) == []
    {:ok, expired} = Enrollment.invite(f.admin, f.enrollment.id, "expired@example.test")

    Repo.update!(
      Ecto.Changeset.change(expired.invitation,
        expires_at: DateTime.add(DateTime.utc_now(:second), -1)
      )
    )

    assert {:error, :invalid_invitation} = Identity.accept_invitation(expired.token, %{})
  end

  test "parent invalidations contain no payload and unrelated families receive no event" do
    f = enrollment_fixture()

    Phoenix.PubSub.subscribe(
      Instantflow.PubSub,
      "organization:#{f.admin.organization_id}:user:#{f.parent.user_id}"
    )

    {:ok, other} = Enrollment.create(f.admin, f.version.workflow_id, Ecto.UUID.generate())

    {:ok, _} =
      Tenant.raw(f.admin.organization_id, fn ->
        WorkflowRuntime.invalidate_lists(f.admin.organization_id, other.ticket_id)
      end)

    refute_receive :enrollments_changed

    {:ok, _} =
      Tenant.raw(f.admin.organization_id, fn ->
        WorkflowRuntime.invalidate_lists(f.admin.organization_id, f.enrollment.ticket_id)
      end)

    assert_receive :enrollments_changed
    refute_receive {:ticket_changed, _, _}
  end
end
