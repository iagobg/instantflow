defmodule Instantflow.EnrollmentFixtures do
  @moduledoc "School scenario setup using supported catalog, participant and record commands."
  import Instantflow.IdentityFixtures
  alias Instantflow.{Access, BuilderFixtures, Identity, Participants, Repo, WorkflowRuntime}
  alias Instantflow.Identity.{Department, Membership}
  alias Instantflow.WorkflowRuntime.ParticipantPages

  def install(actor, departments) do
    Instantflow.Examples.install(actor, "enrollment", %{
      "roles" => %{
        "guardian" => ["external"],
        "admissions" => ["admissions", "admin"],
        "academic" => ["head"],
        "finance" => ["finance"],
        "it" => ["it"]
      },
      "departments" => departments
    })
  end

  def create_record(actor, workflow_id) do
    {:ok, created} =
      WorkflowRuntime.command(actor, %{
        "operation" => "create",
        "workflow_id" => workflow_id,
        "key" => Ecto.UUID.generate()
      })

    %{id: created["ticket_id"], ticket_id: created["ticket_id"]}
  end

  def link(actor, parent, id) do
    {:ok, result} = Participants.command(actor, relationship_command(id, parent.id, "create", 0))

    {:ok, verified} =
      Participants.command(
        actor,
        relationship_command(id, parent.id, "verify", result["revision"])
      )

    Instantflow.Tenant.read(actor, fn _ ->
      Repo.get!(Instantflow.Participants.Relationship, verified["relationship_id"])
    end)
  end

  def relationship_command(id, member_id, operation, revision),
    do: %{
      "ticket_id" => id,
      "membership_id" => member_id,
      "relationship" => "family",
      "operation" => operation,
      "expected_revision" => revision,
      "key" => Ecto.UUID.generate()
    }

  def revoke(f) do
    Participants.command(
      f.admin,
      relationship_command(f.enrollment.id, f.parent.id, "revoke", f.link.revision)
    )
  end

  def enrollment_fixture do
    admin = staff_fixture()

    members =
      for role <- ~w(academic finance it), into: %{} do
        member = staff_fixture("staff")
        department = Repo.insert!(%Department{organization_id: admin.organization_id, name: role})

        {:ok, _} =
          Access.grant(
            admin,
            member.id,
            department.id,
            if(role == "academic", do: "head", else: role)
          )

        {role, Identity.scope(member.user_id, member.organization_id)}
      end

    departments =
      Map.new(members, fn {role, member} ->
        grant =
          Enum.find(member.grants, &(&1.role == if(role == "academic", do: "head", else: role)))

        {role <> "_department", grant.department_id}
      end)
      |> Map.put("admissions_department", admin.department_id)

    {:ok, version} = install(admin, departments)
    enrollment = create_record(admin, version.workflow_id)
    parent = BuilderFixtures.invite_external(admin, "family-#{Ecto.UUID.generate()}@example.test")
    link = link(admin, parent, enrollment.id)

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

  def pdf, do: "%PDF-1.4" <> <<10>> <> "Documento sintético sem dados reais" <> <<10>> <> "%%EOF"

  def upload(actor, id, filename, bytes),
    do: Instantflow.PrivateDocuments.upload(actor, id, "application", "document", filename, bytes)

  def portal(f, actor \\ nil),
    do:
      ParticipantPages.get(
        actor || f.parent,
        f.version.workflow_id,
        "family_portal",
        f.enrollment.id
      )

  def parent_save(f, values),
    do: staff_save(f.parent, f.enrollment.ticket_id, "application", values)

  def parent_submit(f) do
    {:ok, data} = portal(f)

    ParticipantPages.transition(
      f.parent,
      f.version.workflow_id,
      "family_portal",
      f.enrollment.id,
      hd(data.actions).id,
      data.revision,
      nil,
      Ecto.UUID.generate()
    )
  end

  def staff_save(actor, ticket_id, section, values) do
    {:ok, data} = WorkflowRuntime.get(actor, ticket_id)

    WorkflowRuntime.command(
      actor,
      Instantflow.CollaborationFixtures.section_command(data, section, values)
    )
  end

  def second_school(f) do
    org =
      Repo.insert!(%Instantflow.Identity.Organization{
        id: System.unique_integer([:positive]) + 1000,
        slug: "other-#{Ecto.UUID.generate()}",
        name: "Outra escola"
      })

    department = Repo.insert!(%Department{organization_id: org.id, name: "Secretaria"})

    for actor <- [f.admin, f.parent] do
      Repo.insert!(%Membership{
        organization_id: org.id,
        department_id: department.id,
        user_id: actor.user_id,
        role: actor.role
      })
    end

    admin = Identity.scope(f.admin.user_id, org.id)
    parent = Identity.scope(f.parent.user_id, org.id)

    departments =
      Map.new(~w(admissions academic finance it), &{&1 <> "_department", department.id})

    {:ok, version} = install(admin, departments)

    %{
      admin: admin,
      parent: parent,
      enrollment: create_record(admin, version.workflow_id),
      version: version
    }
  end
end
