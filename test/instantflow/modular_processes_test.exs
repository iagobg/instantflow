defmodule Instantflow.ModularProcessesTest do
  use Instantflow.DataCase, async: true
  import Instantflow.IdentityFixtures
  import Instantflow.OperationsFixtures
  alias Instantflow.{Operations, Repo, Tenant, WorkflowCatalog, WorkflowRuntime}
  alias Instantflow.WorkflowCatalog.{Templates, Workspaces, Definition}
  alias Instantflow.Operations.{Line, Batch}

  test "two item-service processes have independent catalogs, resources, reports and command keys" do
    actor = staff_fixture()
    first = install_operations(actor, "restaurant", "Pedidos do restaurante")
    second = install_operations(actor, "equipment", "Locação de equipamentos")
    assert Operations.default_workflow(actor) == nil

    make = fn workflow, operation, attrs ->
      Operations.command(
        actor,
        Map.merge(attrs, %{
          "workflow_id" => workflow,
          "operation" => operation,
          "key" => Ecto.UUID.generate()
        })
      )
    end

    attrs = %{
      "name" => "Item",
      "price" => 1200,
      "category" => "Itens",
      "destination" => "Entrega"
    }

    assert {:ok, p1} = make.(first.workflow_id, "save_product", attrs)
    assert {:ok, _} = make.(second.workflow_id, "save_product", Map.put(attrs, "price", 9900))
    resource = %{"operation" => "add_resource", "key" => "same-key", "name" => "01"}

    assert {:ok, r1} =
             Operations.command(actor, Map.put(resource, "workflow_id", first.workflow_id))

    assert {:ok, r2} =
             Operations.command(actor, Map.put(resource, "workflow_id", second.workflow_id))

    assert {:ok, session} =
             make.(first.workflow_id, "open_session", %{
               "resource_id" => r1["id"],
               "responsible_actor" => "Operador",
               "business_date" => Date.to_iso8601(Operations.today(actor))
             })

    assert {:error, :not_found} =
             make.(first.workflow_id, "open_session", %{
               "resource_id" => r2["id"],
               "responsible_actor" => "Operador",
               "business_date" => Date.to_iso8601(Operations.today(actor))
             })

    assert Operations.visit(actor, session["id"], second.workflow_id) == nil
    product = hd(Operations.workspace(actor, Operations.today(actor), first.workflow_id).products)

    assert {:ok, %{"ids" => [batch_id]}} =
             make.(first.workflow_id, "submit_batch", %{
               "session_id" => session["id"],
               "lines" => [
                 %{
                   "product_id" => p1["id"],
                   "product_revision" => product.revision,
                   "quantity" => 2
                 }
               ]
             })

    assert {:error, :not_found} =
             make.(second.workflow_id, "print_ticket", %{"batch_id" => batch_id})

    assert Operations.workspace(actor, Operations.today(actor), first.workflow_id).report.open_total ==
             2400

    assert Operations.workspace(actor, Operations.today(actor), second.workflow_id).report.open_total ==
             0

    assert {:ok, _} =
             make.(second.workflow_id, "close_day", %{
               "business_date" => Date.to_iso8601(Operations.today(actor))
             })

    assert Operations.workspace(actor, Operations.today(actor), first.workflow_id).report.closed ==
             nil

    assert {:error, :workspace_required} =
             WorkflowRuntime.command(actor, %{
               "operation" => "create",
               "key" => Ecto.UUID.generate(),
               "workflow_id" => first.workflow_id
             })

    assert_raise Ecto.ConstraintError, fn ->
      Tenant.transaction(actor, fn _ ->
        Repo.insert!(%Line{
          organization_id: actor.organization_id,
          workflow_id: second.workflow_id,
          batch_id: batch_id,
          product_id: p1["id"],
          name: "Inválido",
          unit_price: 1,
          quantity: 1,
          notes: ""
        })
      end)
    end

    assert Repo.get!(Batch, batch_id).workflow_id == first.workflow_id
  end

  test "starters are drafts; publishing creates independent reusable processes and preserves interchange" do
    actor = staff_fixture()
    assert Workspaces.installed(actor) == []
    assert {:ok, draft} = Templates.new(actor, "rental", "Locações", "item_service")
    assert Workspaces.installed(actor) == []

    labels = %{
      "resource" => "Balcão",
      "resources" => "Balcões",
      "catalog" => "Equipamentos",
      "actor" => "Atendente",
      "destination" => "Depósito"
    }

    definition = put_in(draft.definition, ["interface", "labels"], labels)

    assert {:ok, saved} =
             Templates.save(actor, draft.id, draft.revision, definition, draft.bindings)

    assert {:ok, published} = Templates.publish(actor, saved.id, saved.revision)
    assert Workspaces.labels(published.definition) == labels
    assert {:ok, exported} = Templates.export(actor, :version, published.id)

    assert {:ok, imported} =
             Templates.import(actor, exported.json, %{"template_key" => "another_rental"})

    assert Workspaces.operational?(imported.definition)
    assert imported.definition["interface"]["labels"] == labels
    assert imported.bindings == %{"roles" => %{}, "departments" => %{}}
    assert length(Workspaces.installed(actor)) == 1

    assert {:error, :incompatible_workspace} =
             WorkflowCatalog.publish(
               actor,
               Templates.starter("rental", "Alteração incompatível"),
               %{
                 "roles" => %{"requester" => ["admin"], "reviewer" => ["admin"]},
                 "departments" => %{"responsible" => actor.department_id}
               },
               1
             )
  end

  test "school starters are copyable definitions with independent keys and retained capability contracts" do
    actor = staff_fixture()

    for {type, name} <- [{"enrollment", "Admissões"}, {"incident", "Casos reservados"}] do
      assert {:ok, draft} = Templates.new(actor, "custom_" <> type, name, type)

      assert Workspaces.pages(draft.definition) ==
               Workspaces.pages(Instantflow.Examples.definition(type))

      assert draft.definition["name"] == name
      assert draft.definition["template_key"] == "custom_" <> type
      assert :ok = Definition.validate(draft.definition)
      invalid = Map.put(draft.definition, "sections", [])
      assert {:error, _} = Definition.validate(invalid)
    end

    assert Workspaces.navigation(actor) == []
    assert Workspaces.navigation(actor) == []
    assert Workspaces.installed(actor) == []
  end

  test "operational block access uses symbolic process roles rather than administrator-only screens" do
    admin = staff_fixture()
    operator = staff_fixture("staff")
    other = staff_fixture("staff")
    {:ok, _} = Instantflow.Access.grant(admin, operator.id, operator.department_id, "operations")
    actor = Instantflow.Identity.scope(operator.user_id, operator.organization_id)
    definition = Templates.starter("service", "Atendimentos", "item_service")

    {:ok, version} =
      WorkflowCatalog.publish(admin, definition, %{
        "roles" => %{"operator" => ["operations"]},
        "departments" => %{"service_department" => operator.department_id}
      })

    assert {:ok, _} =
             Operations.command(actor, %{
               "operation" => "add_resource",
               "workflow_id" => version.workflow_id,
               "key" => Ecto.UUID.generate(),
               "name" => "Balcão 01"
             })

    assert Operations.workspace(actor, Operations.today(actor), version.workflow_id) != nil
    assert Operations.workspace(other, Operations.today(actor), version.workflow_id) == nil

    assert {:error, :forbidden} =
             Operations.command(other, %{
               "operation" => "add_resource",
               "workflow_id" => version.workflow_id,
               "key" => Ecto.UUID.generate(),
               "name" => "Inválido"
             })
  end
end
