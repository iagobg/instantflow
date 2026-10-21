defmodule Instantflow.EnrollmentFixtures do
  import Instantflow.IdentityFixtures
  alias Instantflow.{Access, Enrollment, Identity, Repo, WorkflowRuntime}
  alias Instantflow.Enrollment.GuardianLink
  alias Instantflow.Identity.{Department, Membership}

  def enrollment_fixture do
    admin = staff_fixture()

    members =
      for role <- ~w(academic finance it), into: %{} do
        member = staff_fixture("staff")
        d = Repo.insert!(%Department{organization_id: admin.organization_id, name: role})

        {:ok, _} =
          Access.grant(admin, member.id, d.id, if(role == "academic", do: "head", else: role))

        {role, Identity.scope(member.user_id, member.organization_id)}
      end

    departments =
      Map.new(members, fn {role, m} ->
        grant = Enum.find(m.grants, &(&1.role == if(role == "academic", do: "head", else: role)))
        {role <> "_department", grant.department_id}
      end)
      |> Map.put("admissions_department", admin.department_id)

    {:ok, version} = Enrollment.install(admin, departments)
    {:ok, enrollment} = Enrollment.create(admin, version.workflow_id, Ecto.UUID.generate())

    {:ok, invitation} =
      Enrollment.invite(
        admin,
        enrollment.id,
        "guardian#{System.unique_integer([:positive])}@example.test"
      )

    {:ok, user} =
      Identity.accept_invitation(invitation.token, %{
        "name" => "Responsável fictício",
        "password" => "fictional-password-123"
      })

    parent = Identity.scope(user.id, admin.organization_id)
    link = Repo.get_by!(GuardianLink, enrollment_id: enrollment.id, membership_id: parent.id)
    {:ok, _} = Enrollment.verify(admin, link.id, true)

    %{
      admin: admin,
      members: members,
      departments: departments,
      version: version,
      enrollment: enrollment,
      parent: parent,
      link: link
    }
  end

  def parent_values(document),
    do: %{
      "student_name" => "Estudante fictício",
      "guardian_name" => "Responsável fictício",
      "school_year" => "6º ano",
      "document" => document
    }

  def pdf, do: "%PDF-1.4\nDocumento sintético sem dados reais\n%%EOF"

  def parent_save(f, values) do
    {:ok, d} = Enrollment.get(f.parent, f.enrollment.id)

    Enrollment.save(
      f.parent,
      d.id,
      values,
      d.stage_revision,
      d.section_revision,
      Ecto.UUID.generate()
    )
  end

  def parent_submit(f) do
    {:ok, d} = Enrollment.get(f.parent, f.enrollment.id)
    Enrollment.submit(f.parent, d.id, d.revision, d.section_revision, Ecto.UUID.generate())
  end

  def staff_save(actor, ticket_id, section, values) do
    {:ok, data} = WorkflowRuntime.get(actor, ticket_id)

    WorkflowRuntime.command(
      actor,
      Instantflow.CollaborationFixtures.section_command(data, section, values)
    )
  end

  def second_school(f) do
    # The shared school reserves ID 1 without advancing PostgreSQL's sequence.
    # Match the other multi-school fixtures instead of depending on prior tests.
    org =
      Repo.insert!(%Instantflow.Identity.Organization{
        id: System.unique_integer([:positive]) + 1000,
        slug: "other-#{System.unique_integer([:positive])}",
        name: "Outra escola"
      })

    d = Repo.insert!(%Department{organization_id: org.id, name: "Secretaria"})

    for a <- [f.admin, f.parent] do
      Repo.insert!(%Membership{
        organization_id: org.id,
        department_id: d.id,
        user_id: a.user_id,
        role: a.role
      })
    end

    admin = Identity.scope(f.admin.user_id, org.id)
    parent = Identity.scope(f.parent.user_id, org.id)
    deps = Map.new(~w(admissions academic finance it), &{&1 <> "_department", d.id})
    {:ok, v} = Enrollment.install(admin, deps)
    {:ok, e} = Enrollment.create(admin, v.workflow_id, Ecto.UUID.generate())
    %{admin: admin, parent: parent, enrollment: e, version: v}
  end
end
