defmodule Instantflow.WorkflowRuntime.ParticipantPagesTest do
  use Instantflow.DataCase, async: true
  import Instantflow.IdentityFixtures

  alias Instantflow.{
    BuilderFixtures,
    Participants,
    WorkflowRuntime,
    FinanceFixtures,
    PrivateDocuments
  }

  alias Instantflow.WorkflowRuntime.{ParticipantPages, Projections}
  alias Instantflow.WorkflowCatalog.{Definition, Templates, Interchange}

  test "declared projection narrows existing authority and commands preserve unselected values" do
    f = fixture()

    assert {:ok, _} =
             FinanceFixtures.save(f.visitor, f.id, "customer_details", %{
               "description" => "Visível",
               "private_marker" => "DO-NOT-PROJECT"
             })

    assert {:ok, _} =
             FinanceFixtures.save(f.clerk, f.id, "request", %{"summary" => "INTERNAL-ONLY"})

    assert {:ok, data} = ParticipantPages.get(f.visitor, f.version.workflow_id, "my_packet", f.id)
    assert Enum.map(data.fields, & &1.ref) == ["customer_details.description"]
    refute inspect(data) =~ "DO-NOT-PROJECT"
    refute inspect(data) =~ "INTERNAL-ONLY"

    assert {:error, :not_found} =
             ParticipantPages.get(f.other, f.version.workflow_id, "my_packet", f.id)

    assert {:error, :not_found} =
             ParticipantPages.get(f.subject, f.version.workflow_id, "my_packet", f.id)

    assert Projections.participant_options(f.subject) == []

    assert Projections.participant_search(f.subject, f.version.workflow_id, "my_packet").total ==
             0

    assert Projections.participant_search(f.visitor, nil, "my_packet").total == 0

    assert Projections.participant_search(f.visitor, f.version.workflow_id, "my_packet").total ==
             1

    assert WorkflowRuntime.search(f.visitor).total == 0
    assert WorkflowRuntime.list(f.visitor) == []
    assert Instantflow.WorkflowCatalog.Views.options(f.visitor) == []
    observed = %{stage_revision: data.stage_revision, section_revision: hd(data.fields).revision}

    assert {:ok, _} =
             ParticipantPages.save(
               f.visitor,
               f.version.workflow_id,
               "my_packet",
               f.id,
               "customer_details",
               %{"description" => "Corrigido"},
               observed,
               Ecto.UUID.generate()
             )

    assert {:ok, full} = WorkflowRuntime.get(f.visitor, f.id)

    assert Enum.find(full.sections, &(&1.key == "customer_details")).values["private_marker"] ==
             "DO-NOT-PROJECT"

    assert {:error, :conflict} =
             ParticipantPages.save(
               f.visitor,
               f.version.workflow_id,
               "my_packet",
               f.id,
               "customer_details",
               %{"description" => "Obsoleto"},
               observed,
               Ecto.UUID.generate()
             )

    assert {:error, :forbidden} =
             ParticipantPages.save(
               f.visitor,
               f.version.workflow_id,
               "my_packet",
               f.id,
               "customer_details",
               %{"private_marker" => "forged"},
               observed,
               Ecto.UUID.generate()
             )

    assert {:error, :forbidden} =
             ParticipantPages.transition(
               f.visitor,
               f.version.workflow_id,
               "my_packet",
               f.id,
               "complete",
               full.ticket.revision,
               nil,
               Ecto.UUID.generate()
             )
  end

  test "document correction uses guarded commands and current revocation wins over pinned publication" do
    f = fixture()
    {:ok, data} = ParticipantPages.get(f.visitor, f.version.workflow_id, "my_packet", f.id)

    assert {:ok, _} =
             ParticipantPages.save(
               f.visitor,
               f.version.workflow_id,
               "my_packet",
               f.id,
               "customer_details",
               %{"description" => "Defeito sintético"},
               %{stage_revision: data.stage_revision, section_revision: hd(data.fields).revision},
               Ecto.UUID.generate()
             )

    key = Ecto.UUID.generate()

    assert {:ok, doc} =
             ParticipantPages.upload(
               f.visitor,
               f.version.workflow_id,
               "my_packet",
               f.id,
               "customer_details.evidence",
               "evidence.pdf",
               Instantflow.EnrollmentFixtures.pdf(),
               key
             )

    assert {:ok, ^doc} =
             ParticipantPages.upload(
               f.visitor,
               f.version.workflow_id,
               "my_packet",
               f.id,
               "customer_details.evidence",
               "evidence.pdf",
               Instantflow.EnrollmentFixtures.pdf(),
               key
             )

    {:ok, data} = ParticipantPages.get(f.visitor, f.version.workflow_id, "my_packet", f.id)

    assert {:error, :attachment_not_ready} =
             ParticipantPages.transition(
               f.visitor,
               f.version.workflow_id,
               "my_packet",
               f.id,
               "send_packet",
               data.revision,
               nil,
               Ecto.UUID.generate()
             )

    assert {:ok, _} = PrivateDocuments.review(f.admin, doc.object_key, true)
    {:ok, data} = ParticipantPages.get(f.visitor, f.version.workflow_id, "my_packet", f.id)

    assert {:ok, _} =
             ParticipantPages.transition(
               f.visitor,
               f.version.workflow_id,
               "my_packet",
               f.id,
               "send_packet",
               data.revision,
               nil,
               Ecto.UUID.generate()
             )

    assert {:ok, _} =
             Instantflow.WorkflowFixtures.transition(
               f.admin,
               f.id,
               "request_changes",
               "PRIVATE CORRECTION REASON"
             )

    {:ok, draft} = Templates.clone(f.admin, f.version.id)

    changed =
      f.definition
      |> Map.put("interface", %{
        "pages" => [%{"key" => "staff", "label" => "Nova interface", "blocks" => ["records"]}]
      })
      |> rename()

    {:ok, saved} = Templates.save(f.admin, draft.id, draft.revision, changed, f.bindings)
    assert {:ok, _} = Templates.publish(f.admin, saved.id, saved.revision)
    assert {:ok, old} = ParticipantPages.get(f.visitor, f.version.workflow_id, "my_packet", f.id)
    assert old.page_key == "my_packet" and old.status == "Documentação solicitada"
    refute inspect(old) =~ "PRIVATE CORRECTION REASON"
    assert Enum.any?(old.actions, &(&1.id == "send_packet"))

    assert {:ok, fallback} =
             ParticipantPages.get(f.visitor, f.version.workflow_id, "unknown_page", f.id)

    assert fallback.page_key == "my_packet"

    assert {:ok, _} =
             Participants.command(
               f.admin,
               BuilderFixtures.participant_command(f.id, f.visitor.id, "revoke", 2)
             )

    assert {:error, :not_found} =
             ParticipantPages.get(f.visitor, f.version.workflow_id, "my_packet", f.id)

    assert {:error, :not_found} =
             ParticipantPages.upload(
               f.visitor,
               f.version.workflow_id,
               "my_packet",
               f.id,
               "customer_details.evidence",
               "evidence.pdf",
               Instantflow.EnrollmentFixtures.pdf(),
               key
             )

    assert {:error, :not_found} = PrivateDocuments.download(f.visitor, doc.object_key)
    assert Projections.participant_options(f.visitor) == []
  end

  test "parent staff grant, page visibility and projection audience remain independent" do
    f = fixture()
    parent = staff_fixture("parent")

    assert {:error, :not_found} =
             ParticipantPages.get(parent, f.version.workflow_id, "my_packet", f.id)

    {:ok, {_, grant}} =
      Instantflow.Access.grant(f.admin, parent.id, parent.department_id, "teacher")

    assert {:ok, data} = ParticipantPages.get(parent, f.version.workflow_id, "my_packet", f.id)
    assert Enum.all?(data.fields, &(not &1.editable?))
    assert Projections.participant_search(parent, f.version.workflow_id, "my_packet").total == 1
    assert {:ok, _} = Instantflow.Access.revoke(f.admin, grant.id)

    assert {:error, :not_found} =
             ParticipantPages.get(parent, f.version.workflow_id, "my_packet", f.id)

    hidden =
      put_in(
        f.definition,
        ["interface", "pages", Access.at(1), "participant", "visibility_roles"],
        ["reviewer"]
      )

    version =
      BuilderFixtures.install(f.admin, Map.put(hidden, "template_key", "hidden_page"), f.bindings)

    id = create(f.clerk, version)
    link(f.admin, f.visitor, id, "claimant")
    assert {:ok, _} = WorkflowRuntime.get(f.visitor, id)

    assert {:error, :not_found} =
             ParticipantPages.get(f.visitor, version.workflow_id, "my_packet", id)
  end

  test "portable page contract roundtrips and unsupported combinations fail with paths" do
    definition = BuilderFixtures.participant_page_definition()
    assert :ok = Definition.validate(definition)
    assert {:ok, ^definition} = Interchange.decode(Interchange.encode(definition))

    for {key, value} <- [
          {"fields", ["missing.value"]},
          {"documents", ["customer_details.description"]},
          {"actions", ["missing"]},
          {"visibility_roles", ["unknown"]}
        ] do
      invalid =
        put_in(definition, ["interface", "pages", Access.at(1), "participant", key], value)

      assert {:error, errors} = Definition.validate(invalid)
      assert Enum.any?(errors, &String.contains?(&1, "interface.pages.my_packet.participant"))
    end
  end

  defp fixture do
    admin = staff_fixture()
    clerk = staff_fixture("staff")
    visitor = BuilderFixtures.invite_external(admin, "page-#{Ecto.UUID.generate()}@example.test")
    other = BuilderFixtures.invite_external(admin, "page-#{Ecto.UUID.generate()}@example.test")
    subject = BuilderFixtures.invite_external(admin, "page-#{Ecto.UUID.generate()}@example.test")
    definition = BuilderFixtures.participant_page_definition()

    bindings = %{
      "roles" => %{
        "requester" => ["staff"],
        "reviewer" => ["admin", "teacher"],
        "visitor" => ["external"]
      },
      "departments" => %{"responsible" => admin.department_id}
    }

    version = BuilderFixtures.install(admin, definition, bindings)
    id = create(clerk, version)
    link(admin, visitor, id, "claimant")
    link(admin, subject, id, "observer")

    {:ok, _} =
      Instantflow.WorkflowFixtures.transition(
        admin,
        id,
        "request_changes",
        "Solicitação sintética"
      )

    %{
      admin: admin,
      clerk: clerk,
      visitor: visitor,
      other: other,
      subject: subject,
      id: id,
      version: version,
      definition: definition,
      bindings: bindings
    }
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
end
