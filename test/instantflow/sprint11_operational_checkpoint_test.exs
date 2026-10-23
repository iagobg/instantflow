defmodule Instantflow.Sprint11OperationalCheckpointTest do
  use Instantflow.DataCase, async: false
  import Instantflow.IdentityFixtures
  alias Instantflow.{Access, Operations, WorkflowRuntime}
  alias Instantflow.WorkflowCatalog.Templates

  defp install(actor) do
    json = File.read!(Path.expand("../fixtures/sprint11/supper_room.json", __DIR__))
    {:ok, draft} = Templates.import(actor, json)

    bindings = %{
      "roles" => %{"host" => ["operations"]},
      "departments" => %{"service_team" => actor.department_id}
    }

    {:ok, saved} = Templates.save(actor, draft.id, draft.revision, draft.definition, bindings)
    {:ok, version} = Templates.publish(actor, draft.id, saved.revision)
    version
  end

  defp command(actor, version, operation, attrs) do
    Map.merge(attrs, %{
      "workflow_id" => version.workflow_id,
      "operation" => operation,
      "key" => Ecto.UUID.generate()
    })
    |> then(&Operations.command(actor, &1))
  end

  test "independent restaurant captures prices, splits destinations and rolls back a late settlement failure" do
    admin = staff_fixture()
    operator = staff_fixture("staff")
    assert {:ok, _} = Access.grant(admin, operator.id, operator.department_id, "operations")
    version = install(admin)
    {:ok, resource} = command(operator, version, "add_resource", %{"name" => "Mesa 12"})

    lines =
      for {name, destination, price} <- [{"Sopa", "Cozinha", 2500}, {"Asado", "Parrilla", 8000}] do
        {:ok, product} =
          command(operator, version, "save_product", %{
            "name" => name,
            "destination" => destination,
            "price" => price,
            "category" => "Menu"
          })

        %{
          "product_id" => product["id"],
          "product_revision" => Repo.get!(Instantflow.Operations.Product, product["id"]).revision,
          "quantity" => 1
        }
      end

    opening = %{
      "resource_id" => resource["id"],
      "responsible_actor" => "Ana",
      "business_date" => Operations.today(operator)
    }

    {:ok, visit} = command(operator, version, "open_session", opening)

    {:ok, batches} =
      command(operator, version, "submit_batch", %{"session_id" => visit["id"], "lines" => lines})

    data = Operations.visit(operator, visit["id"], version.workflow_id)
    assert Operations.actor_name(data.session) == "Ana"
    assert Enum.map(data.batches, & &1.destination) == ["Cozinha", "Parrilla"]
    assert data.total == 10500

    product = Repo.get!(Instantflow.Operations.Product, hd(lines)["product_id"])

    assert {:ok, _} =
             command(operator, version, "save_product", %{
               "id" => product.id,
               "revision" => product.revision,
               "name" => "Sopa revisada",
               "category" => "Menu",
               "destination" => "Cozinha",
               "price" => 9900
             })

    assert Operations.visit(operator, visit["id"], version.workflow_id).total == 10500
    assert hd(hd(data.batches).lines).name == "Sopa"

    for id <- batches["ids"],
        do: assert({:ok, _} = command(operator, version, "handoff", %{"batch_id" => id}))

    {:ok, before} = WorkflowRuntime.get(operator, data.session.ticket_id)

    tables = [
      Instantflow.Operations.Receipt,
      Instantflow.WorkflowRuntime.Receipt,
      Instantflow.WorkflowRuntime.Event,
      Instantflow.Delivery.Message
    ]

    counts = Enum.map(tables, &Repo.aggregate(&1, :count))
    setting = :max_pending_deliveries_per_organization
    previous = Application.fetch_env(:instantflow, setting)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:instantflow, setting, value)
        :error -> Application.delete_env(:instantflow, setting)
      end
    end)

    closing = %{
      "workflow_id" => version.workflow_id,
      "operation" => "settle",
      "key" => Ecto.UUID.generate(),
      "session_id" => visit["id"],
      "expected_total" => 10500,
      "payment_method" => "pix"
    }

    Application.put_env(:instantflow, setting, 0)
    assert {:error, :queue_full} = Operations.command(operator, closing)
    assert {:ok, after_failure} = WorkflowRuntime.get(operator, data.session.ticket_id)
    assert before.ticket == after_failure.ticket
    assert before.sections == after_failure.sections
    assert Operations.visit(operator, visit["id"], version.workflow_id).session.status == "open"
    assert Enum.map(tables, &Repo.aggregate(&1, :count)) == counts

    Application.put_env(:instantflow, setting, 1000)
    assert {:ok, result} = Operations.command(operator, closing)
    assert {:ok, ^result} = Operations.command(operator, closing)

    assert Operations.workspace(operator, Operations.today(operator), version.workflow_id).report.sales ==
             10500

    assert {:ok, next} = command(operator, version, "open_session", opening)
    assert next["id"] != visit["id"]
    grant = Enum.find(Access.load(operator).grants, &(&1.role == "operations"))
    assert {:ok, _} = Access.revoke(admin, grant.id)
    assert {:error, :forbidden} = Operations.command(operator, closing)
    assert {:error, :not_found} = command(admin, version, "settle", %{})
  end

  test "pinned payment methods survive republication and retired actor payloads fail closed" do
    admin = staff_fixture()
    assert {:ok, _} = Access.grant(admin, admin.id, admin.department_id, "operations")
    version = install(admin)
    {:ok, resource} = command(admin, version, "add_resource", %{"name" => "Balcão"})

    attrs = %{
      "resource_id" => resource["id"],
      "responsible_actor" => "Nome histórico",
      "business_date" => Operations.today(admin)
    }

    {:ok, first} = command(admin, version, "open_session", attrs)
    {:ok, draft} = Templates.clone(admin, version.id)

    definition =
      put_in(draft.definition, ["interface", "operations", "payment_methods"], ["cash"])

    definition =
      put_in(definition, ["interface", "access"], %{
        "view" => ["host"],
        "configure" => ["host"],
        "operate" => ["host"]
      })

    {:ok, saved} = Templates.save(admin, draft.id, draft.revision, definition, draft.bindings)
    {:ok, _next_version} = Templates.publish(admin, saved.id, saved.revision)

    assert {:ok, _} =
             command(admin, version, "settle", %{
               "session_id" => first["id"],
               "expected_total" => 0,
               "payment_method" => "pix"
             })

    {:ok, second} = command(admin, version, "open_session", attrs)

    assert {:error, :invalid_values} =
             command(admin, version, "settle", %{
               "session_id" => second["id"],
               "expected_total" => 0,
               "payment_method" => "pix"
             })

    assert {:ok, _} =
             command(admin, version, "settle", %{
               "session_id" => second["id"],
               "expected_total" => 0,
               "payment_method" => "cash"
             })

    assert {:error, :invalid_values} =
             command(
               admin,
               version,
               "open_session",
               Map.put(attrs, "waiter", "Nome histórico")
             )
  end

  test "late settlement failure also rolls back a composed finance completion" do
    f = Instantflow.FinanceFixtures.finance_fixture()

    definition =
      f.version.definition
      |> Map.put("template_key", "supplies_counter")
      |> Map.put("capabilities", ~w(core finance operations))
      |> Map.put("interface", %{
        "operations" => Instantflow.WorkflowCatalog.OperationalContract.defaults(),
        "pages" => [
          %{"key" => "counter", "label" => "Bancada", "blocks" => ["resources", "settlement"]}
        ],
        "lifecycle" => %{"close_transition" => "finish"},
        "access" => Map.new(~w(view configure operate), &{&1, ~w(requester operations finance)})
      })

    {:ok, version} = Instantflow.WorkflowCatalog.publish(f.admin, definition, f.version.bindings)
    {:ok, resource} = command(f.operations, version, "add_resource", %{"name" => "Bancada"})

    {:ok, visit} =
      command(f.requester, version, "open_session", %{
        "resource_id" => resource["id"],
        "responsible_actor" => "Técnica",
        "business_date" => Operations.today(f.requester)
      })

    session = Operations.visit(f.requester, visit["id"], version.workflow_id).session
    id = session.ticket_id

    assert {:ok, _} =
             Instantflow.FinanceFixtures.save(f.requester, id, "request", %{
               "summary" => "Reposição",
               "justification" => "Sintética",
               "quantity" => 1,
               "amount" => 6000
             })

    assert {:ok, _} = Instantflow.WorkflowFixtures.transition(f.requester, id, "submit")
    assert {:ok, _} = Instantflow.WorkflowFixtures.transition(f.head, id, "academic_approve")
    assert {:ok, _} = Instantflow.WorkflowFixtures.transition(f.finance, id, "reserve")

    assert {:ok, _} =
             Instantflow.FinanceFixtures.save(f.operations, id, "order", %{
               "reference" => "pedido-1"
             })

    assert {:ok, _} = Instantflow.WorkflowFixtures.transition(f.operations, id, "order")

    assert {:ok, _} =
             Instantflow.FinanceFixtures.save(f.operations, id, "delivery", %{"received" => 1})

    tables = [
      Instantflow.Finance.Entry,
      Instantflow.Operations.Receipt,
      Instantflow.WorkflowRuntime.Receipt,
      Instantflow.WorkflowRuntime.Event,
      Instantflow.Delivery.Message
    ]

    counts = Enum.map(tables, &Repo.aggregate(&1, :count))
    balances = Instantflow.Finance.accounts(f.finance)
    before_hold = Repo.get_by!(Instantflow.Finance.Hold, ticket_id: id)
    {:ok, before} = WorkflowRuntime.get(f.operations, id)
    setting = :max_pending_deliveries_per_organization
    previous = Application.fetch_env(:instantflow, setting)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:instantflow, setting, value)
        :error -> Application.delete_env(:instantflow, setting)
      end
    end)

    Application.put_env(:instantflow, setting, 0)

    closing = %{
      "workflow_id" => version.workflow_id,
      "operation" => "settle",
      "key" => Ecto.UUID.generate(),
      "session_id" => session.id,
      "expected_total" => 0,
      "payment_method" => "cash"
    }

    assert {:error, :queue_full} = Operations.command(f.operations, closing)
    assert Repo.get!(Instantflow.Operations.Session, session.id) == session
    assert Repo.get_by!(Instantflow.Finance.Hold, ticket_id: id) == before_hold
    assert Instantflow.Finance.accounts(f.finance) == balances
    assert Enum.map(tables, &Repo.aggregate(&1, :count)) == counts
    assert {:ok, after_failure} = WorkflowRuntime.get(f.operations, id)
    assert before.ticket == after_failure.ticket
    assert before.sections == after_failure.sections
    Application.put_env(:instantflow, setting, 1000)
    assert {:ok, result} = Operations.command(f.operations, closing)
    assert {:ok, ^result} = Operations.command(f.operations, closing)
    assert Repo.aggregate(Instantflow.Finance.Entry, :count) == hd(counts) + 1
  end
end
