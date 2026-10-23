defmodule Instantflow.BuilderRecreationTest do
  use Instantflow.DataCase, async: true
  import Instantflow.IdentityFixtures
  alias Instantflow.{BuilderFixtures, Operations, WorkflowRuntime, WorkflowFixtures}
  alias Instantflow.WorkflowCatalog.{Bindings, Templates}

  test "core-only import needs no finance or operational setup" do
    admin = staff_fixture()
    requester = staff_fixture("staff")
    definition = BuilderFixtures.core_definition()

    bindings = %{
      "roles" => %{"requester" => ["staff"], "reviewer" => ["admin"]},
      "departments" => %{"responsible" => admin.department_id}
    }

    version = BuilderFixtures.install(admin, definition, bindings)

    {:ok, created} =
      WorkflowRuntime.command(requester, %{
        "operation" => "create",
        "workflow_id" => version.workflow_id,
        "key" => WorkflowFixtures.key()
      })

    id = created["ticket_id"]
    assert {:ok, _} = WorkflowFixtures.save(requester, id, %{"summary" => "Verificação"})
    assert {:ok, _} = WorkflowFixtures.transition(admin, id, "complete")
    assert {:ok, %{ticket: %{stage: "closed"}}} = WorkflowRuntime.get(requester, id)
  end

  test "equipment service desk is independently configured and pinned through import/publication" do
    admin = staff_fixture()
    definition = BuilderFixtures.equipment_definition()

    bindings = %{
      "roles" => %{"technician" => ["admin"]},
      "departments" => %{"workshop" => admin.department_id}
    }

    version = BuilderFixtures.install(admin, definition, bindings)

    command = fn operation, values ->
      Operations.command(
        admin,
        Map.merge(values, %{
          "operation" => operation,
          "workflow_id" => version.workflow_id,
          "key" => WorkflowFixtures.key()
        })
      )
    end

    assert {:ok, resource} = command.("add_resource", %{"name" => "Bancada 01"})

    assert {:ok, opened} =
             command.("open_session", %{
               "resource_id" => resource["id"],
               "responsible_actor" => "Técnico",
               "business_date" => Date.to_iso8601(Operations.today(admin))
             })

    {:ok, draft} = Templates.clone(admin, version.id)
    revised = Map.put(definition, "name", "Assistência revisada")
    {:ok, saved} = Templates.save(admin, draft.id, draft.revision, revised, bindings)
    assert {:ok, _} = Templates.publish(admin, saved.id, saved.revision)

    assert {:ok, _} =
             command.("settle", %{
               "session_id" => opened["id"],
               "expected_total" => 0,
               "payment_method" => "cash"
             })

    visit = Operations.visit(admin, opened["id"], version.workflow_id)
    assert {:ok, data} = WorkflowRuntime.get(admin, visit.session.ticket_id)
    assert data.ticket.workflow_version_id == version.id
    assert data.ticket.stage == "collected"
    assert Enum.any?(data.events, &(&1.operation == "handover"))
  end

  test "equipment desk combines invited external correction, directory, private release and resource settlement" do
    admin = staff_fixture()
    suffix = System.unique_integer([:positive])
    customer = BuilderFixtures.invite_external(admin, "equipment-#{suffix}@example.test")
    unrelated = BuilderFixtures.invite_external(admin, "unrelated-#{suffix}@example.test")
    assert customer.role == "external" and customer.grants == []
    assert Repo.aggregate(Instantflow.Enrollment.Record, :count) == 0
    assert Repo.aggregate(Instantflow.Enrollment.GuardianLink, :count) == 0

    version =
      BuilderFixtures.install(admin, BuilderFixtures.equipment_participant_definition(), %{
        "roles" => %{"technician" => ["admin"], "customer" => ["external"]},
        "departments" => %{"workshop" => admin.department_id}
      })

    command = fn operation, values ->
      Operations.command(
        admin,
        Map.merge(values, %{
          "operation" => operation,
          "workflow_id" => version.workflow_id,
          "key" => Ecto.UUID.generate()
        })
      )
    end

    {:ok, resource} = command.("add_resource", %{"name" => "Bancada externa"})

    {:ok, opened} =
      command.("open_session", %{
        "resource_id" => resource["id"],
        "responsible_actor" => "Técnico",
        "business_date" => Date.to_iso8601(Operations.today(admin))
      })

    id = Operations.visit(admin, opened["id"], version.workflow_id).session.ticket_id

    for {operation, revision} <- [{"create", 0}, {"verify", 1}] do
      assert {:ok, _} =
               Instantflow.Participants.command(
                 admin,
                 BuilderFixtures.participant_command(id, customer.id, operation, revision)
                 |> Map.put("relationship", "owner")
               )
    end

    [{_, reference}] =
      Instantflow.Participants.Directory.options(admin, id, "work_order", "customer_link")

    assert {:ok, _} =
             Instantflow.FinanceFixtures.save(admin, id, "work_order", %{
               "customer_link" => reference
             })

    assert {:error, :not_found} = WorkflowRuntime.get(unrelated, id)

    assert {:ok, _} =
             WorkflowFixtures.transition(
               admin,
               id,
               "request_details",
               "Envie o comprovante sintético"
             )

    {:ok, doc} =
      Instantflow.PrivateDocuments.upload(
        customer,
        id,
        "repair_packet",
        "proof",
        "equipment.pdf",
        Instantflow.EnrollmentFixtures.pdf()
      )

    assert {:ok, _} =
             Instantflow.FinanceFixtures.save(customer, id, "repair_packet", %{
               "fault" => "Equipamento não liga",
               "proof" => doc.object_key
             })

    assert {:error, :attachment_not_ready} =
             WorkflowFixtures.transition(customer, id, "send_details")

    assert {:ok, _} = Instantflow.PrivateDocuments.review(admin, doc.object_key, true)
    assert {:ok, _} = WorkflowFixtures.transition(customer, id, "send_details")

    assert {:ok, _} =
             command.("settle", %{
               "session_id" => opened["id"],
               "expected_total" => 0,
               "payment_method" => "cash"
             })

    assert {:ok, %{ticket: %{stage: "collected"}}} = WorkflowRuntime.get(customer, id)
    assert WorkflowRuntime.search(unrelated).tickets == []
    assert Instantflow.WorkflowCatalog.available(customer) == []
  end

  test "review identifies each missing local mapping without embedding tenant IDs in definitions" do
    admin = staff_fixture()
    {:ok, draft} = Templates.new(admin, "mapping_review", "Mapeamentos")
    assert {:ok, review} = Templates.review(admin, draft.id)
    assert Enum.any?(review.errors, &String.starts_with?(&1, "mapeamentos.roles.requester:"))

    assert Enum.any?(
             review.errors,
             &String.starts_with?(&1, "mapeamentos.departments.responsible:")
           )

    assert {:ok, errors} =
             Instantflow.Tenant.transaction(admin, fn _ ->
               Bindings.errors(
                 draft.definition,
                 %{"roles" => %{}, "departments" => %{"responsible" => -1}},
                 admin.organization_id
               )
             end)

    assert Enum.any?(errors, &String.contains?(&1, "indisponível nesta organização"))
  end
end
