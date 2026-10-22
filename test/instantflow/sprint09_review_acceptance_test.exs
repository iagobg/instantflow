defmodule Instantflow.Sprint09ReviewAcceptanceTest do
  use Instantflow.DataCase, async: true
  import Instantflow.IdentityFixtures

  alias Instantflow.{
    BuilderFixtures,
    Participants,
    PrivateDocuments,
    Repo,
    WorkflowCatalog,
    WorkflowRuntime
  }

  alias Instantflow.Access, as: Grants
  alias Instantflow.Identity.{Department, Membership, User}
  alias Instantflow.WorkflowCatalog.{Definition, Interchange, Templates}

  defp bindings(admin, visitor \\ ["parent", "external"]) do
    %{
      "roles" => %{
        "requester" => ["staff", "teacher"],
        "reviewer" => ["teacher"],
        "visitor" => visitor
      },
      "departments" => %{"responsible" => admin.department_id}
    }
  end

  defp create(actor, version) do
    command = %{
      "operation" => "create",
      "workflow_id" => version.workflow_id,
      "key" => Ecto.UUID.generate()
    }

    {:ok, result} = WorkflowRuntime.command(actor, command)
    {result["ticket_id"], command}
  end

  test "explicit candidate roles are portable and required independently of actor permissions" do
    definition = BuilderFixtures.directory_definition()

    for roles <- [nil, [], ["missing"]] do
      invalid =
        update_in(definition, ["participants", Access.at(0)], fn spec ->
          if roles == nil,
            do: Map.delete(spec, "candidate_roles"),
            else: Map.put(spec, "candidate_roles", roles)
        end)

      assert {:ok, imported} = invalid |> Interchange.encode() |> Interchange.decode()
      assert {:error, errors} = Definition.validate(imported)
      assert Enum.any?(errors, &String.starts_with?(&1, "modelo.participants[0].candidate_roles"))
    end
  end

  test "picker and commands enforce current local eligibility including grants and revoked retries" do
    admin = staff_fixture()
    clerk = staff_fixture("staff")
    eligible = staff_fixture("external")
    ineligible = staff_fixture("parent")
    assert {:ok, {_, grant}} = Grants.grant(admin, eligible.id, admin.department_id, "teacher")

    definition =
      put_in(
        BuilderFixtures.participant_definition(),
        ["participants", Access.at(0), "candidate_roles"],
        ["reviewer"]
      )

    # Eligibility is granted locally; the candidate's base role is not sufficient.
    {:ok, {_, _}} = Grants.grant(admin, clerk.id, admin.department_id, "teacher")
    version = BuilderFixtures.install(admin, definition, bindings(admin))
    {id, _} = create(clerk, version)
    [control] = Participants.controls(clerk, id).controls
    assert Enum.any?(control.candidates, fn {_, member_id} -> member_id == eligible.id end)
    refute Enum.any?(control.candidates, fn {_, member_id} -> member_id == ineligible.id end)

    assert {:error, :ineligible_participant} =
             Participants.command(
               clerk,
               BuilderFixtures.participant_command(id, ineligible.id, "create", 0)
             )

    pending = BuilderFixtures.participant_command(id, eligible.id, "create", 0)
    assert {:ok, _} = Participants.command(clerk, pending)
    verify = BuilderFixtures.participant_command(id, eligible.id, "verify", 1)
    assert {:ok, _} = Participants.command(clerk, verify)
    assert {:ok, _} = Grants.revoke(admin, grant.id)
    assert {:error, :ineligible_participant} = Participants.command(clerk, verify)
    assert {:error, :ineligible_participant} = Participants.command(clerk, pending)

    assert {:error, :ineligible_participant} =
             Participants.command(
               clerk,
               BuilderFixtures.participant_command(id, eligible.id, "verify", 2)
             )

    # Removal remains available even when candidate eligibility has disappeared.
    assert {:ok, _} =
             Participants.command(
               clerk,
               BuilderFixtures.participant_command(id, eligible.id, "revoke", 2)
             )
  end

  test "candidate query and direct commands reject disabled users and other organization memberships" do
    admin = staff_fixture()
    clerk = staff_fixture("staff")
    inactive = staff_fixture("external")
    disabled_member = staff_fixture("external")
    shared_identity = staff_fixture("external")
    other = Instantflow.EnrollmentFixtures.second_school(%{admin: admin, parent: shared_identity})
    Repo.get!(User, inactive.user_id) |> Ecto.Changeset.change(active: false) |> Repo.update!()

    Repo.get!(Membership, disabled_member.id)
    |> Ecto.Changeset.change(active: false)
    |> Repo.update!()

    definition = BuilderFixtures.participant_definition()

    version =
      BuilderFixtures.install(admin, definition, %{
        "roles" => %{"requester" => ["staff"], "reviewer" => ["admin"], "visitor" => ["external"]},
        "departments" => %{"responsible" => admin.department_id}
      })

    {id, _} = create(clerk, version)
    [control] = Participants.controls(admin, id).controls

    refute Enum.any?(control.candidates, fn {_, member_id} ->
             member_id in [inactive.id, disabled_member.id, other.parent.id]
           end)

    assert Enum.any?(control.candidates, fn {_, member_id} -> member_id == shared_identity.id end)

    assert {:ok, _} =
             Participants.command(
               admin,
               BuilderFixtures.participant_command(id, shared_identity.id, "create", 0)
             )

    for {member, reason} <- [
          {inactive, :ineligible_participant},
          {disabled_member, :not_found},
          {other.parent, :not_found}
        ] do
      assert {:error, ^reason} =
               Participants.command(
                 admin,
                 BuilderFixtures.participant_command(id, member.id, "create", 0)
               )
    end
  end

  test "candidate eligibility remains pinned when a new publication changes eligible roles" do
    admin = staff_fixture()
    clerk = staff_fixture("staff")
    external = staff_fixture("external")
    definition = BuilderFixtures.participant_definition("pinned_candidates")

    local_bindings = %{
      "roles" => %{"requester" => ["staff"], "reviewer" => ["admin"], "visitor" => ["external"]},
      "departments" => %{"responsible" => admin.department_id}
    }

    version = BuilderFixtures.install(admin, definition, local_bindings)
    {old_id, _} = create(clerk, version)
    {:ok, draft} = Templates.clone(admin, version.id)
    revised = put_in(definition, ["participants", Access.at(0), "candidate_roles"], ["requester"])
    {:ok, saved} = Templates.save(admin, draft.id, draft.revision, revised, local_bindings)
    {:ok, latest} = Templates.publish(admin, saved.id, saved.revision)
    {new_id, _} = create(clerk, latest)
    [old] = Participants.controls(admin, old_id).controls
    [new] = Participants.controls(admin, new_id).controls
    assert Enum.any?(old.candidates, fn {_, member_id} -> member_id == external.id end)
    refute Enum.any?(new.candidates, fn {_, member_id} -> member_id == external.id end)

    for {operation, revision} <- [{"create", 0}, {"verify", 1}] do
      assert {:ok, _} =
               Participants.command(
                 admin,
                 BuilderFixtures.participant_command(old_id, external.id, operation, revision)
               )
    end

    assert {:error, :ineligible_participant} =
             Participants.command(
               admin,
               BuilderFixtures.participant_command(new_id, external.id, "create", 0)
             )

    assert {:ok, _} =
             Participants.command(
               admin,
               BuilderFixtures.participant_command(new_id, clerk.id, "create", 0)
             )
  end

  test "parent and external memberships use explicit scoped staff grants in declared processes" do
    admin = staff_fixture()
    clerk = staff_fixture("staff")
    visitor = staff_fixture("external")
    plain_parent = staff_fixture("parent")
    plain_external = staff_fixture("external")

    version =
      BuilderFixtures.install(admin, BuilderFixtures.document_definition(), bindings(admin))

    {id, _} = create(clerk, version)

    for role <- ["parent", "external"] do
      {id, _} = create(clerk, version)
      manager = staff_fixture(role)

      wrong_department =
        Repo.insert!(%Department{organization_id: admin.organization_id, name: "Other #{role}"})

      {:ok, {_, wrong_grant}} = Grants.grant(admin, manager.id, wrong_department.id, "teacher")
      assert Participants.controls(manager, id).controls == []
      {:ok, {_, grant}} = Grants.grant(admin, manager.id, admin.department_id, "teacher")
      assert length(Participants.controls(manager, id).controls) == 1
      assert {:ok, data} = WorkflowRuntime.get(manager, id)
      assert Enum.any?(data.section_definitions, &(&1["key"] == "customer_details"))
      assert Enum.any?(WorkflowRuntime.list(manager), &(&1.id == id))
      assert Enum.any?(WorkflowCatalog.available(manager), &(&1.id == version.id))
      {own_id, creation} = create(manager, version)
      assert {:ok, _} = WorkflowRuntime.get(manager, own_id)
      assert {:ok, _} = WorkflowRuntime.command(manager, creation)

      # Relationship authority never substitutes for staff manager/reviewer scope.
      for {operation, revision} <- [{"create", 0}, {"verify", 1}] do
        assert {:ok, _} =
                 Participants.command(
                   manager,
                   BuilderFixtures.participant_command(id, visitor.id, operation, revision)
                 )
      end

      {:ok, doc} =
        PrivateDocuments.upload(
          visitor,
          id,
          "customer_details",
          "evidence",
          "proof.pdf",
          Instantflow.EnrollmentFixtures.pdf()
        )

      assert {:ok, _} = PrivateDocuments.review(manager, doc.object_key, true)
      assert Participants.controls(visitor, id).controls == []
      assert {:error, :forbidden} = PrivateDocuments.review(visitor, doc.object_key, true)

      assert {:ok, _} = Grants.revoke(admin, grant.id)
      assert Participants.controls(manager, id).controls == []
      assert {:error, :not_found} = WorkflowRuntime.get(manager, id)
      # The remaining grant in a different department still permits creation,
      # but grants no section or review authority for this assigned department.
      assert {:error, :forbidden} = PrivateDocuments.review(manager, doc.object_key, true)
      assert {:ok, _} = Grants.revoke(admin, wrong_grant.id)
      assert {:error, :forbidden} = WorkflowRuntime.command(manager, creation)
      refute Enum.any?(WorkflowCatalog.available(manager), &(&1.id == version.id))

      assert {:error, :forbidden} =
               WorkflowRuntime.command(manager, %{creation | "key" => Ecto.UUID.generate()})
    end

    for member <- [plain_parent, plain_external] do
      assert Participants.controls(member, id).controls == []
      assert {:error, :not_found} = WorkflowRuntime.get(member, id)
      refute Enum.any?(WorkflowCatalog.available(member), &(&1.id == version.id))

      assert {:error, :forbidden} =
               WorkflowRuntime.command(member, %{
                 "operation" => "create",
                 "workflow_id" => version.workflow_id,
                 "key" => Ecto.UUID.generate()
               })
    end
  end

  test "legacy school versions retain parent restrictions when a declared version is published" do
    f = Instantflow.EnrollmentFixtures.enrollment_fixture()
    unrelated = staff_fixture("parent")
    {:ok, _} = Grants.grant(f.admin, unrelated.id, f.admin.department_id, "admissions")
    {:ok, _} = Grants.grant(f.admin, f.parent.id, f.admin.department_id, "admissions")
    assert {:error, :not_found} = WorkflowRuntime.get(unrelated, f.enrollment.ticket_id)
    assert {:error, :not_found} = WorkflowRuntime.get(f.parent, f.enrollment.ticket_id)
    assert {:ok, _} = Instantflow.Enrollment.get(f.parent, f.enrollment.id)
    refute Enum.any?(WorkflowCatalog.available(unrelated), &(&1.id == f.version.id))

    assert {:error, :forbidden} =
             WorkflowRuntime.command(unrelated, %{
               "operation" => "create",
               "workflow_id" => f.version.workflow_id,
               "key" => Ecto.UUID.generate()
             })

    definition = BuilderFixtures.participant_definition("enrollment")

    {:ok, draft} = Templates.clone(f.admin, f.version.id)

    {:ok, saved} =
      Templates.save(f.admin, draft.id, draft.revision, definition, %{
        "roles" => %{
          "requester" => ["admissions"],
          "reviewer" => ["admissions"],
          "visitor" => ["parent"]
        },
        "departments" => %{"responsible" => f.admin.department_id}
      })

    {:ok, version} = Templates.publish(f.admin, saved.id, saved.revision)

    assert version.workflow_id == f.version.workflow_id
    {id, _} = create(unrelated, version)
    assert {:ok, _} = WorkflowRuntime.get(unrelated, id)
    assert {:error, :not_found} = WorkflowRuntime.get(unrelated, f.enrollment.ticket_id)
    assert {:ok, _} = Instantflow.Enrollment.get(f.parent, f.enrollment.id)
    pinned = Repo.get!(Instantflow.WorkflowRuntime.Ticket, f.enrollment.ticket_id)
    assert pinned.workflow_version_id == f.version.id

    assert Repo.get!(Instantflow.WorkflowCatalog.Version, f.version.id).definition ==
             f.version.definition
  end
end
