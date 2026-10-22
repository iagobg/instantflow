defmodule Instantflow.OperationsFixtures do
  import Instantflow.IdentityFixtures
  alias Instantflow.Operations

  def operation(actor, operation, attrs \\ %{}) do
    Operations.command(
      actor,
      Map.merge(%{"operation" => operation, "key" => Ecto.UUID.generate()}, attrs)
    )
  end

  def install_operations(actor, key \\ "resource_service", name \\ "Atendimento com itens") do
    definition =
      File.read!(Application.app_dir(:instantflow, "priv/workflows/resource_service.json"))
      |> Jason.decode!()
      |> Map.put("template_key", key)
      |> Map.put("name", name)

    {:ok, version} =
      Instantflow.WorkflowCatalog.publish(actor, definition, %{
        "roles" => %{"operator" => ["admin"]},
        "departments" => %{"service_department" => actor.department_id}
      })

    version
  end

  def operations_fixture do
    actor = staff_fixture()
    install_operations(actor)
    {:ok, %{"id" => resource}} = operation(actor, "add_resource", %{"name" => "Mesa 08"})

    {:ok, %{"id" => soup}} =
      operation(actor, "save_product", %{
        "name" => "Sopa",
        "category" => "Entradas",
        "price" => 2550,
        "destination" => "Cozinha"
      })

    {:ok, %{"id" => asado}} =
      operation(actor, "save_product", %{
        "name" => "Asado",
        "category" => "Carnes",
        "price" => 8000,
        "destination" => "Parrilla"
      })

    %{actor: actor, resource: resource, soup: soup, asado: asado}
  end

  def open_visit(f, date \\ Operations.today()) do
    {:ok, %{"id" => id}} =
      operation(f.actor, "open_session", %{
        "resource_id" => f.resource,
        "waiter" => "Carlos",
        "business_date" => Date.to_iso8601(date)
      })

    id
  end

  def item(actor, id, quantity \\ 1) do
    product = Enum.find(Operations.workspace(actor, Operations.today()).products, &(&1.id == id))

    %{
      "product_id" => id,
      "product_revision" => product.revision,
      "quantity" => quantity,
      "notes" => "Sem coentro"
    }
  end
end
