defmodule Instantflow.ParticipantDirectoryTest do
  use Instantflow.DataCase, async: true
  import Instantflow.IdentityFixtures
  alias Instantflow.{BuilderFixtures, Participants, WorkflowFixtures, WorkflowRuntime}
  alias Instantflow.Participants.Directory
  alias Instantflow.WorkflowCatalog.{Definition, Interchange}

  setup do
    admin = staff_fixture()
    clerk = staff_fixture("staff")
    visitor = staff_fixture("parent")
    unrelated = staff_fixture("parent")
    definition = BuilderFixtures.directory_definition()

    bindings = %{
      "roles" => %{"requester" => ["staff"], "reviewer" => ["admin"], "visitor" => ["parent"]},
      "departments" => %{"responsible" => admin.department_id}
    }

    version = BuilderFixtures.install(admin, definition, bindings)
    id = create(clerk, version)
    relationship = link(admin, id, visitor)

    %{
      admin: admin,
      clerk: clerk,
      visitor: visitor,
      unrelated: unrelated,
      definition: definition,
      version: version,
      id: id,
      relationship: relationship,
      bindings: bindings
    }
  end

  test "only independently authorized record-local relationships appear and non-null references persist",
       f do
    assert Directory.options(f.admin, f.id, "request", "contact") == [
             {f.visitor.user.name, f.relationship}
           ]

    assert Directory.options(f.clerk, f.id, "request", "contact") == []
    assert Directory.options(f.unrelated, f.id, "request", "contact") == []

    assert {:ok, _} =
             WorkflowFixtures.save(f.admin, f.id, %{
               "summary" => "Atendimento",
               "contact" => f.relationship
             })

    assert {:ok, data} = WorkflowRuntime.get(f.admin, f.id)
    assert hd(data.sections).values["contact"] == f.relationship
    assert data.reference_labels["request.contact"][f.relationship] == f.visitor.user.name
    assert {:ok, external} = WorkflowRuntime.get(f.visitor, f.id)
    refute Enum.any?(external.sections, &(&1.key == "request"))

    assert {:error, :invalid_reference} =
             WorkflowFixtures.save(f.clerk, f.id, %{
               "summary" => "Atendimento",
               "contact" => f.relationship
             })
  end

  test "unknown, other-record and other-process IDs are rejected without granting target access",
       f do
    for {definition, version} <- [
          {f.definition, f.version},
          {BuilderFixtures.directory_definition("independent_directory"), nil}
        ] do
      version = version || BuilderFixtures.install(f.admin, definition, f.bindings)
      other_id = create(f.clerk, version)
      other_reference = link(f.admin, other_id, f.visitor)

      assert {:error, :invalid_reference} =
               WorkflowFixtures.save(f.admin, f.id, %{"contact" => other_reference})
    end

    assert {:error, :invalid_reference} =
             WorkflowFixtures.save(f.admin, f.id, %{"contact" => 9_007_199_254_740_991})

    assert {:error, {:invalid_values, _}} =
             WorkflowFixtures.save(f.admin, f.id, %{"contact" => [f.relationship]})
  end

  test "revocation removes labels/options and prevents saves or transitions using stale selections",
       f do
    assert {:ok, _} =
             WorkflowFixtures.save(f.admin, f.id, %{
               "summary" => "Atendimento",
               "contact" => f.relationship
             })

    assert {:ok, _} =
             Participants.command(
               f.admin,
               BuilderFixtures.participant_command(f.id, f.visitor.id, "revoke", 2)
             )

    assert Directory.options(f.admin, f.id, "request", "contact") == []
    assert {:ok, data} = WorkflowRuntime.get(f.admin, f.id)
    assert data.reference_labels["request.contact"] == %{}

    assert {:error, :invalid_reference} =
             WorkflowFixtures.save(f.admin, f.id, %{
               "summary" => "Atendimento",
               "contact" => f.relationship
             })

    assert {:error, :invalid_reference} = WorkflowFixtures.transition(f.admin, f.id, "complete")

    assert {:ok, _} =
             WorkflowFixtures.save(f.admin, f.id, %{"summary" => "Atendimento", "contact" => nil})

    assert {:ok, _} = WorkflowFixtures.transition(f.admin, f.id, "complete")
  end

  test "subject references require a subject relationship and retain portable symbolic declarations",
       f do
    subject =
      f.definition
      |> Map.put("template_key", "subject_directory")
      |> put_in(["participants", Access.at(0), "kind"], "subject")
      |> put_in(
        ["sections", Access.at(0), "fields", Access.at(1), "reference", "target"],
        "subject"
      )

    assert :ok = Definition.validate(subject)
    assert {:ok, ^subject} = subject |> Interchange.encode() |> Interchange.decode()
    version = BuilderFixtures.install(f.admin, subject, f.bindings)
    id = create(f.clerk, version)
    reference = link(f.admin, id, f.visitor)
    assert {:ok, _} = WorkflowFixtures.save(f.admin, id, %{"contact" => reference})
    invalid = put_in(subject, ["participants", Access.at(0), "kind"], "external")
    assert {:error, errors} = Definition.validate(invalid)
    assert Enum.any?(errors, &String.contains?(&1, "reference.target"))

    invalid =
      put_in(
        subject,
        ["sections", Access.at(0), "fields", Access.at(1), "reference", "membership_id"],
        f.visitor.id
      )

    assert {:error, _} = Definition.validate(invalid)
  end

  test "search is bounded and includes an authorized stored selection outside the first page",
       f do
    for _ <- 1..26 do
      member = staff_fixture("parent")
      link(f.admin, f.id, member)
    end

    assert length(Directory.options(f.admin, f.id, "request", "contact")) == 25
    assert Directory.options(f.admin, f.id, "request", "contact", "does-not-exist") == []
    assert {:ok, _} = WorkflowFixtures.save(f.admin, f.id, %{"contact" => f.relationship})

    assert Directory.options(f.admin, f.id, "request", "contact", "does-not-exist") ==
             [{f.visitor.user.name, f.relationship}]

    assert Directory.options(f.unrelated, f.id, "request", "contact", f.visitor.user.name) == []
  end

  test "a shared identity in another organization cannot resolve or submit its references", f do
    alias Instantflow.Identity.{Department, Membership, Organization}

    org =
      Repo.insert!(%Organization{
        id: System.unique_integer([:positive]) + 1000,
        slug: "directory-other-#{System.unique_integer([:positive])}",
        name: "Outra organização"
      })

    department = Repo.insert!(%Department{organization_id: org.id, name: "Atendimento"})

    for {actor, role} <- [{f.clerk, "admin"}, {f.admin, "staff"}, {f.visitor, "parent"}] do
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
    bindings = put_in(f.bindings, ["departments", "responsible"], department.id)
    version = BuilderFixtures.install(manager, BuilderFixtures.directory_definition(), bindings)
    id = create(requester, version)
    reference = link(manager, id, visitor)
    assert Directory.options(requester, f.id, "request", "contact") == []

    assert {:error, :invalid_reference} =
             WorkflowFixtures.save(f.admin, f.id, %{"contact" => reference})

    assert {:error, :invalid_reference} =
             WorkflowFixtures.save(manager, id, %{"contact" => f.relationship})
  end

  defp create(actor, version) do
    {:ok, result} =
      WorkflowRuntime.command(
        actor,
        %{
          "operation" => "create",
          "workflow_id" => version.workflow_id,
          "key" => Ecto.UUID.generate()
        }
      )

    result["ticket_id"]
  end

  defp link(manager, id, member) do
    {:ok, _} =
      Participants.command(
        manager,
        BuilderFixtures.participant_command(id, member.id, "create", 0)
      )

    {:ok, verified} =
      Participants.command(
        manager,
        BuilderFixtures.participant_command(id, member.id, "verify", 1)
      )

    verified["relationship_id"]
  end
end
