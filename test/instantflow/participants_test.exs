defmodule Instantflow.ParticipantsTest do
  use Instantflow.DataCase, async: true
  import Instantflow.IdentityFixtures
  alias Instantflow.{BuilderFixtures, Participants, WorkflowRuntime}
  alias Instantflow.WorkflowCatalog.{Definition, Templates}

  setup do
    admin = staff_fixture()
    clerk = staff_fixture("staff")
    visitor = staff_fixture("parent")
    unrelated = staff_fixture("parent")
    definition = BuilderFixtures.participant_definition()

    bindings = %{
      "roles" => %{"requester" => ["staff"], "reviewer" => ["admin"], "visitor" => ["parent"]},
      "departments" => %{"responsible" => admin.department_id}
    }

    version = BuilderFixtures.install(admin, definition, bindings)

    {:ok, result} =
      WorkflowRuntime.command(clerk, %{
        "operation" => "create",
        "workflow_id" => version.workflow_id,
        "key" => Ecto.UUID.generate()
      })

    %{
      admin: admin,
      clerk: clerk,
      visitor: visitor,
      unrelated: unrelated,
      version: version,
      id: result["ticket_id"],
      definition: definition,
      bindings: bindings
    }
  end

  test "verification is explicit, scoped, revision-safe and separate from administration", f do
    create = BuilderFixtures.participant_command(f.id, f.visitor.id, "create", 0)
    assert {:error, :forbidden} = Participants.command(f.clerk, create)
    assert {:ok, pending} = Participants.command(f.admin, create)
    assert {:ok, ^pending} = Participants.command(f.admin, create)
    assert pending["status"] == "pending"
    assert {:error, :not_found} = WorkflowRuntime.get(f.visitor, f.id)

    verify = BuilderFixtures.participant_command(f.id, f.visitor.id, "verify", 1)
    assert {:ok, verified} = Participants.command(f.admin, verify)
    assert verified["revision"] == 2

    assert {:error, :conflict} =
             Participants.command(f.admin, %{verify | "key" => Ecto.UUID.generate()})

    assert {:error, :idempotency_mismatch} =
             Participants.command(f.admin, %{verify | "expected_revision" => 2})

    assert {:ok, data} = WorkflowRuntime.get(f.visitor, f.id)
    assert Enum.map(data.sections, & &1.key) == ["customer_details"]
    assert Enum.map(WorkflowRuntime.list(f.visitor), & &1.id) == [f.id]
    assert {:error, :not_found} = WorkflowRuntime.get(f.unrelated, f.id)
    assert WorkflowRuntime.list(f.unrelated) == []
    assert {:ok, internal} = WorkflowRuntime.get(f.admin, f.id)
    refute Enum.any?(internal.sections, &(&1.key == "customer_details"))
    refute Enum.any?(data.events, &String.starts_with?(&1.operation, "participant:"))
  end

  test "revocation fences protected mutations and previously successful command replay", f do
    assert {:ok, _} =
             Participants.command(
               f.admin,
               BuilderFixtures.participant_command(f.id, f.visitor.id, "create", 0)
             )

    assert {:ok, _} =
             Participants.command(
               f.admin,
               BuilderFixtures.participant_command(f.id, f.visitor.id, "verify", 1)
             )

    {:ok, data} = WorkflowRuntime.get(f.visitor, f.id)
    section = hd(data.sections)

    save = %{
      "operation" => "save_section",
      "ticket_id" => f.id,
      "section" => "customer_details",
      "values" => %{"description" => "Relato privado"},
      "key" => Ecto.UUID.generate(),
      "expected_stage_revision" => data.ticket.stage_revision,
      "expected_section_revision" => section.revision
    }

    assert {:ok, _} = WorkflowRuntime.command(f.visitor, save)

    assert {:ok, _} =
             Participants.command(
               f.admin,
               BuilderFixtures.participant_command(f.id, f.visitor.id, "revoke", 2)
             )

    assert {:error, :forbidden} = WorkflowRuntime.command(f.visitor, save)
    assert {:error, :not_found} = WorkflowRuntime.get(f.visitor, f.id)
    assert WorkflowRuntime.search(f.visitor).total == 0
  end

  test "relationships and local role mappings remain pinned across publication", f do
    for operation <- ["create", "verify"] do
      revision = if operation == "create", do: 0, else: 1

      assert {:ok, _} =
               Participants.command(
                 f.admin,
                 BuilderFixtures.participant_command(f.id, f.visitor.id, operation, revision)
               )
    end

    revised =
      f.definition
      |> Map.put("name", "Novo atendimento")
      |> Map.delete("participants")
      |> Map.update!("sections", &Enum.reject(&1, fn s -> s["key"] == "customer_details" end))

    {:ok, draft} = Templates.clone(f.admin, f.version.id)
    {:ok, saved} = Templates.save(f.admin, draft.id, draft.revision, revised, f.bindings)
    assert {:ok, _} = Templates.publish(f.admin, saved.id, saved.revision)
    assert {:ok, %{ticket: %{workflow_version_id: pinned}}} = WorkflowRuntime.get(f.visitor, f.id)
    assert pinned == f.version.id

    assert {:ok, _} =
             Participants.command(
               f.admin,
               BuilderFixtures.participant_command(f.id, f.visitor.id, "revoke", 2)
             )

    assert {:error, :not_found} = WorkflowRuntime.get(f.visitor, f.id)
  end

  test "portable contracts reject unknown relationships, recursive managers and local IDs", f do
    unknown =
      put_in(
        f.definition,
        ["sections", Access.at(1), "access", Access.at(0), "relationship"],
        "unknown"
      )

    assert {:error, errors} = Definition.validate(unknown)
    assert Enum.any?(errors, &String.contains?(&1, "relationship"))

    invalid =
      put_in(f.definition, ["participants", Access.at(0), "managers"], [
        %{"role" => "visitor", "scope" => "participant", "relationship" => "claimant"}
      ])

    assert {:error, _} = Definition.validate(invalid)
    invalid = put_in(f.definition, ["participants", Access.at(0), "membership_id"], f.visitor.id)
    assert {:error, _} = Definition.validate(invalid)
    invalid = Map.put(f.definition, "capabilities", ["core"])
    assert {:error, _} = Definition.validate(invalid)
  end

  test "two independently installed processes cannot share relationships implicitly", f do
    other =
      BuilderFixtures.install(
        f.admin,
        BuilderFixtures.participant_definition("other_intake"),
        f.bindings
      )

    {:ok, result} =
      WorkflowRuntime.command(f.clerk, %{
        "operation" => "create",
        "workflow_id" => other.workflow_id,
        "key" => Ecto.UUID.generate()
      })

    for operation <- ["create", "verify"] do
      assert {:ok, _} =
               Participants.command(
                 f.admin,
                 BuilderFixtures.participant_command(
                   f.id,
                   f.visitor.id,
                   operation,
                   if(operation == "create", do: 0, else: 1)
                 )
               )
    end

    assert {:error, :not_found} = WorkflowRuntime.get(f.visitor, result["ticket_id"])
  end

  test "renamed roles, fields, sections and relationships retain the configured authorization",
       f do
    replacements = %{
      "service_intake" => "repair_intake",
      "visitor" => "customer",
      "claimant" => "equipment_owner",
      "customer_details" => "repair_details",
      "description" => "reported_fault"
    }

    definition = rename(f.definition, replacements)

    bindings =
      put_in(f.bindings, ["roles"], %{
        "requester" => ["staff"],
        "reviewer" => ["admin"],
        "customer" => ["parent"]
      })

    version = BuilderFixtures.install(f.admin, definition, bindings)

    {:ok, created} =
      WorkflowRuntime.command(f.clerk, %{
        "operation" => "create",
        "workflow_id" => version.workflow_id,
        "key" => Ecto.UUID.generate()
      })

    id = created["ticket_id"]

    for {operation, revision} <- [{"create", 0}, {"verify", 1}] do
      command =
        BuilderFixtures.participant_command(id, f.visitor.id, operation, revision)
        |> Map.put("relationship", "equipment_owner")

      assert {:ok, _} = Participants.command(f.admin, command)
    end

    assert {:ok, data} = WorkflowRuntime.get(f.visitor, id)
    assert Enum.map(data.sections, & &1.key) == ["repair_details"]
    assert Enum.map(hd(data.section_definitions)["fields"], & &1["key"]) == ["reported_fault"]
    assert {:error, :not_found} = WorkflowRuntime.get(f.unrelated, id)
  end

  defp rename(value, replacements) when is_map(value),
    do: Map.new(value, fn {key, item} -> {key, rename(item, replacements)} end)

  defp rename(value, replacements) when is_list(value),
    do: Enum.map(value, &rename(&1, replacements))

  defp rename(value, replacements), do: Map.get(replacements, value, value)
end
