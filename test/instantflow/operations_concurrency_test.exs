defmodule Instantflow.OperationsConcurrencyTest do
  use Instantflow.RuntimeCase, async: false
  import Ecto.Query
  alias Instantflow.{Identity, Operations, OperatorRepo, Repo, Tenant, WorkflowRuntime}
  alias Instantflow.WorkflowRuntime.Ticket
  alias Instantflow.Identity.{Department, Membership, Organization, User}
  alias Instantflow.Operations.{Batch, DayClose, Line, Product, Receipt, Session}
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

    assert {:ok, %{"id" => id}} = Task.await(held)
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

    assert {:ok, %{"id" => close_id}} = Task.await(held)
    assert OperatorRepo.get!(DayClose, close_id).workflow_id == first
    assert {:error, :day_closed} = Task.await(blocked)
    assert {:ok, _} = Task.await(independent)
  end

  test "commands on separate visits in one workflow commit independently", c do
    [a, b | _] = c.actors
    f = visits(c)
    held = hold_command(c, a, f.workflow, "print_ticket", %{"batch_id" => f.first_batch})
    assert_receive {:command_held, _}, 5000
    parent = self()

    other =
      task(c, fn ->
        result = command(b, f.workflow, "print_ticket", %{"batch_id" => f.second_batch})
        send(parent, {:visit_committed, result})
        result
      end)

    try do
      assert_receive {:visit_committed, {:ok, %{"copy" => 1}}}, 2000
    after
      send(held.pid, :commit)
    end

    assert {:ok, %{"copy" => 1}} = Task.await(held)
    assert {:ok, %{"copy" => 1}} = Task.await(other)
    assert OperatorRepo.get!(Batch, f.first_batch).print_count == 1
    assert OperatorRepo.get!(Batch, f.second_batch).print_count == 1
  end

  test "concurrent prints retain both increments and replay adds no copy", c do
    [a, b | _] = c.actors
    f = visits(c)
    attrs = %{"batch_id" => f.first_batch, "key" => Ecto.UUID.generate()}
    held = hold_command(c, a, f.workflow, "print_ticket", attrs)
    assert_receive {:command_held, _}, 5000

    other =
      task(c, fn -> command(b, f.workflow, "print_ticket", %{"batch_id" => f.first_batch}) end)

    release_after_wait(c, held)
    assert {:ok, first} = Task.await(held)
    assert first["copy"] == 1
    assert {:ok, %{"copy" => 2}} = Task.await(other)
    assert {:ok, ^first} = command(a, f.workflow, "print_ticket", attrs)
    assert OperatorRepo.get!(Batch, f.first_batch).print_count == 2
    assert OperatorRepo.aggregate(from(r in Receipt, where: r.key == ^attrs["key"]), :count) == 1
  end

  test "competing actors cannot open the same resource twice", c do
    [a, b | _] = c.actors
    [workflow | _] = c.workflows
    [resource | _] = c.resources
    held = hold_command(c, a, workflow, "open_session", visit(resource, c.date))
    assert_receive {:command_held, _}, 5000
    other = task(c, fn -> command(b, workflow, "open_session", visit(resource, c.date)) end)
    release_after_wait(c, held)
    assert {:ok, _} = Task.await(held)
    assert {:error, :occupied} = Task.await(other)

    assert OperatorRepo.aggregate(from(s in Session, where: s.resource_id == ^resource), :count) ==
             1
  end

  test "settlement observes a concurrent pending batch", c do
    [a, b | _] = c.actors
    f = visits(c)
    assert {:ok, _} = command(a, f.workflow, "handoff", %{"batch_id" => f.first_batch})
    held = hold_command(c, a, f.workflow, "submit_batch", items(f.first, f.product))
    assert_receive {:command_held, _}, 5000
    other = task(c, fn -> command(b, f.workflow, "settle", checkout(f.first, 100)) end)
    release_after_wait(c, held)
    assert {:ok, _} = Task.await(held)
    assert {:error, :pending_handoff} = Task.await(other)
    assert OperatorRepo.get!(Session, f.first).status == "open"
  end

  test "settlement prevents a queued batch from changing the committed total", c do
    [a, b | _] = c.actors
    f = visits(c)
    assert {:ok, _} = command(a, f.workflow, "handoff", %{"batch_id" => f.first_batch})
    held = hold_command(c, a, f.workflow, "settle", checkout(f.first, 100))
    assert_receive {:command_held, _}, 5000
    other = task(c, fn -> command(b, f.workflow, "submit_batch", items(f.first, f.product)) end)
    release_after_wait(c, held)
    assert {:ok, %{"total" => 100}} = Task.await(held)
    assert {:error, :invalid_state} = Task.await(other)
    assert OperatorRepo.get!(Session, f.first).total == 100
    assert OperatorRepo.aggregate(from(b in Batch, where: b.session_id == ^f.first), :count) == 1

    assert {:ok, %{"copy" => 1}} =
             command(b, f.workflow, "print_ticket", %{"batch_id" => f.first_batch})
  end

  test "cancellation serializes competing cancellation and handoff", c do
    [a, b, third] = c.actors
    f = visits(c)
    attrs = %{"batch_id" => f.first_batch, "reason" => "Cancelled by customer"}
    held = hold_command(c, a, f.workflow, "cancel_batch", attrs)
    assert_receive {:command_held, _}, 5000
    cancel = task(c, fn -> command(b, f.workflow, "cancel_batch", attrs) end)

    handoff =
      task(c, fn -> command(third, f.workflow, "handoff", %{"batch_id" => f.first_batch}) end)

    release_after_wait(c, held, 2)
    assert {:ok, %{"id" => notice}} = Task.await(held)
    assert {:error, :invalid_state} = Task.await(cancel)
    assert {:error, :invalid_state} = Task.await(handoff)
    assert OperatorRepo.get!(Batch, f.first_batch).status == "cancelled"
    assert OperatorRepo.get!(Batch, notice).source_id == f.first_batch

    assert OperatorRepo.aggregate(from(b in Batch, where: b.source_id == ^f.first_batch), :count) ==
             1

    original = OperatorRepo.one!(from l in Line, where: l.batch_id == ^f.first_batch)
    copy = OperatorRepo.one!(from l in Line, where: l.batch_id == ^notice)

    assert {original.name, original.unit_price, original.quantity} ==
             {copy.name, copy.unit_price, copy.quantity}
  end

  test "catalog changes fence submissions and preserve prior line snapshots", c do
    [a, b | _] = c.actors
    f = visits(c)
    attrs = Map.merge(product("Changed"), %{"id" => f.product, "revision" => 2, "price" => 200})
    held = hold_command(c, a, f.workflow, "save_product", attrs)
    assert_receive {:command_held, _}, 5000
    other = task(c, fn -> command(b, f.workflow, "submit_batch", items(f.first, f.product)) end)
    release_after_wait(c, held)
    assert {:ok, _} = Task.await(held)
    assert {:error, :catalog_changed} = Task.await(other)

    assert OperatorRepo.one!(from l in Line, where: l.batch_id == ^f.first_batch).unit_price ==
             100

    fresh =
      put_in(items(f.first, f.product), ["lines"], [
        %{"product_id" => f.product, "product_revision" => 3, "quantity" => 1}
      ])

    assert {:ok, %{"ids" => [batch]}} = command(b, f.workflow, "submit_batch", fresh)
    assert OperatorRepo.one!(from l in Line, where: l.batch_id == ^batch).unit_price == 200
  end

  test "catalog uniqueness remains a domain error during concurrent creation", c do
    [a, b | _] = c.actors
    [workflow | _] = c.workflows
    held = hold_command(c, a, workflow, "save_product", product("Unique"))
    assert_receive {:command_held, _}, 5000
    other = task(c, fn -> command(b, workflow, "save_product", product("Unique")) end)
    release_after_wait(c, held)
    assert {:ok, _} = Task.await(held)
    assert {:error, :duplicate_name} = Task.await(other)
  end

  test "daily close sees a concurrent opening on an earlier business date", c do
    [a, b | _] = c.actors
    [workflow | _] = c.workflows
    [resource | _] = c.resources
    held = hold_command(c, a, workflow, "open_session", visit(resource, Date.add(c.date, -1)))
    assert_receive {:command_held, _}, 5000
    other = task(c, fn -> command(b, workflow, "close_day", %{"business_date" => c.date}) end)
    release_after_wait(c, held)
    assert {:ok, _} = Task.await(held)
    assert {:error, :open_sessions} = Task.await(other)
    refute OperatorRepo.exists?(from d in DayClose, where: d.workflow_id == ^workflow)
  end

  test "daily close waits for settlement and freezes its committed summary", c do
    [a, b | _] = c.actors
    f = visits(c)

    for {session, batch} <- [{f.first, f.first_batch}, {f.second, f.second_batch}] do
      assert {:ok, _} = command(a, f.workflow, "handoff", %{"batch_id" => batch})

      if session == f.second,
        do: assert({:ok, _} = command(a, f.workflow, "settle", checkout(session, 100)))
    end

    held = hold_command(c, a, f.workflow, "settle", checkout(f.first, 100))
    assert_receive {:command_held, _}, 5000
    other = task(c, fn -> command(b, f.workflow, "close_day", %{"business_date" => c.date}) end)
    release_after_wait(c, held)
    assert {:ok, _} = Task.await(held)
    assert {:ok, %{"id" => close}} = Task.await(other)
    summary = OperatorRepo.get!(DayClose, close).summary
    assert summary["sales"] == 200
    assert summary["settled_count"] == 2
    assert summary["open_count"] == 0

    assert {:ok, %{"copy" => 1}} =
             command(b, f.workflow, "print_ticket", %{"batch_id" => f.first_batch})
  end

  test "settlement waits for the runtime ticket before locking its session", c do
    [a, b | _] = c.actors
    f = visits(c)
    assert {:ok, _} = command(a, f.workflow, "handoff", %{"batch_id" => f.first_batch})
    session = OperatorRepo.get!(Session, f.first)
    transition = Instantflow.WorkflowFixtures.transition_command(a, session.ticket_id, "settle")
    parent = self()

    generic =
      task(c, fn ->
        Tenant.transaction(a, fn _ ->
          Repo.one!(from t in Ticket, where: t.id == ^session.ticket_id, lock: "FOR UPDATE")
          send(parent, :runtime_ticket_held)

          receive do
            :continue ->
              case WorkflowRuntime.command(a, transition) do
                {:error, reason} -> Repo.rollback(reason)
                result -> result
              end
          after
            15_000 -> Repo.rollback(:barrier_timeout)
          end
        end)
      end)

    assert_receive :runtime_ticket_held, 5000
    settle = task(c, fn -> command(b, f.workflow, "settle", checkout(f.first, 100)) end)

    try do
      assert wait_for_waiters(c, 1)
      # An owner probe must still be able to acquire the session while checkout
      # waits on the ticket; reversing that order would expose a deadlock cycle.
      assert %{rows: [[id]]} =
               Postgrex.query!(
                 c.observer,
                 "SELECT id FROM service_sessions WHERE id=$1 FOR UPDATE NOWAIT",
                 [session.id]
               )

      assert id == session.id
    after
      send(generic.pid, :continue)
    end

    assert {:error, :checkout_required} = Task.await(generic)
    assert {:ok, %{"total" => 100}} = Task.await(settle)
    assert OperatorRepo.get!(Ticket, session.ticket_id).stage == "settled"
  end

  test "an enclosing transaction retains an exclusive gate before later configuration", c do
    [a, b | _] = c.actors
    f = visits(c)
    parent = self()

    held =
      task(c, fn ->
        Repo.transaction(fn ->
          assert {:ok, %{"copy" => 1}} =
                   command(a, f.workflow, "print_ticket", %{"batch_id" => f.first_batch})

          send(parent, :outer_command_held)

          receive do
            :commit ->
              command(a, f.workflow, "save_product", product("Added in same transaction"))
          after
            15_000 -> Repo.rollback(:barrier_timeout)
          end
        end)
      end)

    assert_receive :outer_command_held, 5000

    other =
      task(c, fn -> command(b, f.workflow, "print_ticket", %{"batch_id" => f.second_batch}) end)

    release_after_wait(c, held)
    assert {:ok, {:ok, %{"id" => product}}} = Task.await(held)
    assert OperatorRepo.get!(Product, product).name == "Added in same transaction"
    assert {:ok, %{"copy" => 1}} = Task.await(other)
  end

  defp visits(c) do
    [actor | _] = c.actors
    [workflow | _] = c.workflows
    [resource | _] = c.resources

    {:ok, %{"id" => another_resource}} =
      command(actor, workflow, "add_resource", %{"name" => "Another"})

    {:ok, %{"id" => product}} = command(actor, workflow, "save_product", product("Item"))

    pairs =
      for resource <- [resource, another_resource] do
        {:ok, %{"id" => session}} =
          command(actor, workflow, "open_session", visit(resource, c.date))

        {:ok, %{"ids" => [batch]}} =
          command(actor, workflow, "submit_batch", items(session, product))

        {session, batch}
      end

    [{first, first_batch}, {second, second_batch}] = pairs

    %{
      workflow: workflow,
      product: product,
      first: first,
      first_batch: first_batch,
      second: second,
      second_batch: second_batch
    }
  end

  defp release_after_wait(c, held, count \\ 1) do
    try do
      assert wait_for_waiters(c, count)
    after
      send(held.pid, :commit)
    end
  end

  defp items(session, product),
    do: %{
      "session_id" => session,
      "lines" => [%{"product_id" => product, "product_revision" => 2, "quantity" => 1}]
    }

  defp checkout(session, total),
    do: %{"session_id" => session, "payment_method" => "cash", "expected_total" => total}

  defp task(c, fun) do
    Task.Supervisor.async_nolink(c.supervisor, fn ->
      Repo.put_dynamic_repo(c.runtime)
      fun.()
    end)
  end

  defp hold_command(c, actor, workflow, operation, attrs) do
    parent = self()

    task(c, fn ->
      handler = {__MODULE__, make_ref()}

      :ok =
        :telemetry.attach(
          handler,
          [:instantflow, :repo, :query],
          &__MODULE__.hold_receipt/4,
          {self(), parent}
        )

      try do
        command(actor, workflow, operation, attrs)
      after
        :telemetry.detach(handler)
      end
    end)
  end

  def hold_receipt(_, _, metadata, {owner, parent}) do
    if self() == owner and metadata.source == "operation_receipts" and
         String.starts_with?(metadata.query, "INSERT") do
      [[backend]] = Repo.query!("SELECT pg_backend_pid()").rows
      send(parent, {:command_held, backend})

      receive do
        :commit -> :ok
      after
        15_000 -> Repo.rollback(:barrier_timeout)
      end
    end
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
      Map.merge(
        %{
          "operation" => operation,
          "workflow_id" => workflow,
          "key" => Ecto.UUID.generate()
        },
        attrs
      )
    )
  end

  defp product(name),
    do: %{"name" => name, "category" => "Test", "destination" => "Service", "price" => 100}

  defp visit(resource, date),
    do: %{"resource_id" => resource, "business_date" => date, "responsible_actor" => "Test"}
end
