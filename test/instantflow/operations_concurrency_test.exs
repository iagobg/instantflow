defmodule Instantflow.OperationsConcurrencyTest do
  use Instantflow.RuntimeCase, async: false
  alias Instantflow.{Identity, Operations, OperatorRepo, Repo}
  alias Instantflow.Identity.{Department, Membership, Organization, User}
  alias Instantflow.Operations.{DayClose, Product, Session}
  import Instantflow.OperationsFixtures, only: [install_operations: 3]

  setup c do
    suffix = System.unique_integer([:positive])
    organization = OperatorRepo.insert!(%Organization{slug: "operations-#{suffix}", name: "Test"})

    department =
      OperatorRepo.insert!(%Department{organization_id: organization.id, name: "Service"})

    actors =
      for n <- 1..3 do
        user =
          OperatorRepo.insert!(%User{
            email: "operations-#{suffix}-#{n}@example.test",
            name: "Operator",
            password_hash: "unused-by-runtime-command-tests"
          })

        OperatorRepo.insert!(%Membership{
          organization_id: organization.id,
          department_id: department.id,
          user_id: user.id,
          role: "admin"
        })

        Identity.scope(user.id, organization.id)
      end

    [actor | _] = actors
    first = install_operations(actor, "first", "First service")
    second = install_operations(actor, "second", "Second service")
    date = Operations.today(actor)

    resources =
      for version <- [first, second] do
        {:ok, %{"id" => id}} =
          command(actor, version.workflow_id, "add_resource", %{"name" => "Resource"})

        id
      end

    observer =
      start_supervised!(
        Supervisor.child_spec({Postgrex, c.owner_config ++ [database: c.database]}, id: :observer)
      )

    %{
      actors: actors,
      workflows: [first.workflow_id, second.workflow_id],
      resources: resources,
      date: date,
      observer: observer,
      supervisor: start_supervised!(Task.Supervisor)
    }
  end

  test "independent workflows commit while another workflow command is held", c do
    [a, b | _] = c.actors
    [first, second] = c.workflows
    parent = self()
    held = hold_command(c, a, first, "save_product", product("Same name"))
    assert_receive {:command_held, held_backend}, 5000

    other =
      task(c, fn ->
        result = command(b, second, "save_product", product("Same name"))
        send(parent, {:independent_committed, result})
        result
      end)

    try do
      assert_receive {:independent_committed, {:ok, %{"id" => id}}}, 2000
      assert OperatorRepo.get!(Product, id).workflow_id == second
      assert held_backend > 0
    after
      send(held.pid, :commit)
    end

    assert {:ok, {:ok, %{"id" => id}}} = Task.await(held)
    assert OperatorRepo.get!(Product, id).workflow_id == first
    assert {:ok, _} = Task.await(other)
  end

  test "a day close fences its workflow while another workflow can open a visit", c do
    [a, b, other_actor] = c.actors
    [first, second] = c.workflows
    [first_resource, second_resource] = c.resources
    parent = self()
    held = hold_command(c, a, first, "close_day", %{"business_date" => c.date})
    assert_receive {:command_held, _}, 5000

    blocked = task(c, fn -> command(b, first, "open_session", visit(first_resource, c.date)) end)

    independent =
      task(c, fn ->
        result = command(other_actor, second, "open_session", visit(second_resource, c.date))
        send(parent, {:other_workflow_opened, result})
        result
      end)

    try do
      assert wait_for_waiters(c, 1)
      assert_receive {:other_workflow_opened, {:ok, %{"id" => id}}}, 2000
      assert OperatorRepo.get!(Session, id).workflow_id == second
    after
      send(held.pid, :commit)
    end

    assert {:ok, {:ok, %{"id" => close_id}}} = Task.await(held)
    assert OperatorRepo.get!(DayClose, close_id).workflow_id == first
    assert {:error, :day_closed} = Task.await(blocked)
    assert {:ok, _} = Task.await(independent)
  end

  defp task(c, fun) do
    Task.Supervisor.async_nolink(c.supervisor, fn ->
      Repo.put_dynamic_repo(c.runtime)
      fun.()
    end)
  end

  defp hold_command(c, actor, workflow, operation, attrs) do
    parent = self()

    task(c, fn ->
      Repo.transaction(fn ->
        result = command(actor, workflow, operation, attrs)
        assert {:ok, _} = result
        [[backend]] = Repo.query!("SELECT pg_backend_pid()").rows
        send(parent, {:command_held, backend})

        receive do
          :commit -> result
        after
          15_000 -> Repo.rollback(:barrier_timeout)
        end
      end)
    end)
  end

  defp wait_for_waiters(c, expected, attempts \\ 1000)
  defp wait_for_waiters(_, _, 0), do: false

  defp wait_for_waiters(c, expected, attempts) do
    [[count]] =
      Postgrex.query!(
        c.observer,
        """
        SELECT count(*) FROM pg_stat_activity
        WHERE datname=$1 AND usename='instantflow_runtime' AND wait_event_type='Lock'
        """,
        [c.database]
      ).rows

    count >= expected or wait_for_waiters(c, expected, attempts - 1)
  end

  defp command(actor, workflow, operation, attrs) do
    Operations.command(
      actor,
      Map.merge(attrs, %{
        "operation" => operation,
        "workflow_id" => workflow,
        "key" => Ecto.UUID.generate()
      })
    )
  end

  defp product(name),
    do: %{"name" => name, "category" => "Test", "destination" => "Service", "price" => 100}

  defp visit(resource, date),
    do: %{"resource_id" => resource, "business_date" => date, "responsible_actor" => "Test"}
end
