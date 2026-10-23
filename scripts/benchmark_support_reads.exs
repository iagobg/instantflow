System.put_env("READ_BENCHMARK_LIBRARY", "true")
Code.require_file("benchmark_reads.exs", __DIR__)

defmodule Instantflow.SupportReadFixtures do
  @moduledoc false
  alias Instantflow.{OperatorRepo, Identity}
  alias Instantflow.Identity.{Organization, Department, Membership, User}
  alias Instantflow.WorkflowCatalog.{Workflow, Version, Definition}
  alias Instantflow.WorkflowRuntime.{Ticket, Section}
  def surface, do: "operations"

  def prepare do
    for table <-
          ~w(tickets workflow_versions catalog_products service_resources service_sessions fulfillment_batches fulfillment_lines),
        do: OperatorRepo.query!("ANALYZE " <> table)
  end

  def populate(index, hash, d) do
    org =
      OperatorRepo.insert!(%Organization{
        slug: "read-#{index}",
        name: "Synthetic read tenant #{index}"
      })

    dep = OperatorRepo.insert!(%Department{organization_id: org.id, name: "Readers"})
    hidden_dep = OperatorRepo.insert!(%Department{organization_id: org.id, name: "Hidden"})

    members =
      for n <- 1..5 do
        user =
          OperatorRepo.insert!(%User{
            email: "read#{index}-#{n}@example.invalid",
            name: "Synthetic reader",
            password_hash: hash
          })

        OperatorRepo.insert!(%Membership{
          organization_id: org.id,
          department_id: dep.id,
          user_id: user.id,
          role: "staff"
        })
      end

    [first | _] = members
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    processes =
      for i <- 1..d.processes do
        key = "read_process_#{i}"
        definition = definition(key, d.width, d.surface)
        :ok = Definition.validate(definition)

        workflow =
          OperatorRepo.insert!(%Workflow{
            organization_id: org.id,
            key: key,
            name: definition["name"]
          })

        rows =
          for n <- 1..d.versions do
            %{
              organization_id: org.id,
              workflow_id: workflow.id,
              number: n,
              definition: put_in(definition, ["stages", Access.at(0), "label"], "Pinned #{n}"),
              bindings: %{
                "roles" => %{"operator" => ["staff"]},
                "departments" => %{"service_department" => dep.id}
              },
              published_by_id: first.user_id,
              inserted_at: now,
              updated_at: now
            }
          end

        {_, versions} = OperatorRepo.insert_all(Version, rows, returning: [:id, :number])
        {workflow, Enum.sort_by(versions, & &1.number)}
      end

    {workflow, versions} = hd(processes)

    count =
      case d.shape do
        "equal" -> 1000
        "uneven" when index == 1 -> 7000
        "uneven" when index <= 4 -> 334
        "uneven" -> 333
      end

    fields = definition("fixture", d.width, d.surface)["sections"] |> hd() |> Map.fetch!("fields")
    values = Map.new(fields, &{&1["key"], String.duplicate("s", 1024)})

    rows =
      for n <- 1..count do
        %{
          organization_id: org.id,
          workflow_id: workflow.id,
          workflow_version_id: Enum.at(versions, rem(n - 1, d.used_versions)).id,
          requester_id: first.user_id,
          assigned_department_id:
            if(rem(n - 1, d.hidden + 1) == 0, do: dep.id, else: hidden_dep.id),
          stage: "settled",
          revision: 1,
          stage_revision: 1,
          inserted_at: now,
          updated_at: now
        }
      end

    tickets =
      rows
      |> Enum.chunk_every(500)
      |> Enum.flat_map(fn chunk ->
        {_, inserted} = OperatorRepo.insert_all(Ticket, chunk, returning: [:id])
        inserted
      end)

    for chunk <- Enum.chunk_every(tickets, 200) do
      OperatorRepo.insert_all(
        Section,
        Enum.map(
          chunk,
          &%{
            organization_id: org.id,
            ticket_id: &1.id,
            key: "service",
            values: values,
            revision: 1,
            inserted_at: now,
            updated_at: now
          }
        )
      )
    end

    expected = div(count + d.hidden, d.hidden + 1)
    support = populate_support(org, workflow, tickets, count)

    Enum.map(members, fn member ->
      {Identity.scope(member.user_id, org.id), workflow.id, Map.put(support, :tickets, expected)}
    end)
  end

  defp definition(key, _width, _surface) do
    File.read!(Application.app_dir(:instantflow, "priv/workflows/resource_service.json"))
    |> Jason.decode!()
    |> Map.put("template_key", key)
  end

  defp populate_support(org, workflow, tickets, count) do
    alias Instantflow.Operations.{Product, Resource, Session, Batch, Line}

    {_, products} =
      OperatorRepo.insert_all(
        Product,
        for(
          n <- 1..1000,
          do: %{
            organization_id: org.id,
            workflow_id: workflow.id,
            name: "Product #{n}",
            category: "Synthetic",
            price: 500,
            destination: "Kitchen",
            active: true,
            revision: 1
          }
        ),
        returning: [:id]
      )

    {_, resources} =
      OperatorRepo.insert_all(
        Resource,
        for(
          n <- 1..1000,
          do: %{
            organization_id: org.id,
            workflow_id: workflow.id,
            name: "Resource #{n}"
          }
        ),
        returning: [:id]
      )

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    date = Date.utc_today()

    sessions =
      tickets
      |> Enum.with_index()
      |> Enum.map(fn {ticket, i} ->
        %{
          organization_id: org.id,
          workflow_id: workflow.id,
          ticket_id: ticket.id,
          resource_id: Enum.at(resources, rem(i, 1000)).id,
          resource_name: "Captured resource",
          waiter: "Synthetic actor",
          business_date: date,
          status: "settled",
          total: 1000,
          payment_method: "pix",
          opened_at: now,
          settled_at: now
        }
      end)

    sessions =
      sessions
      |> Enum.chunk_every(500)
      |> Enum.flat_map(fn chunk ->
        {_, rows} = OperatorRepo.insert_all(Session, chunk, returning: [:id])
        rows
      end)

    {_, batches} =
      OperatorRepo.insert_all(
        Batch,
        Enum.map(sessions, fn session ->
          %{
            organization_id: org.id,
            workflow_id: workflow.id,
            session_id: session.id,
            destination: "Kitchen",
            kind: "order",
            status: "handed",
            waiter: "Synthetic actor",
            inserted_at: now
          }
        end),
        returning: [:id]
      )

    lines =
      batches
      |> Enum.with_index()
      |> Enum.flat_map(fn {batch, i} ->
        for j <- 0..1,
            do: %{
              organization_id: org.id,
              workflow_id: workflow.id,
              batch_id: batch.id,
              product_id: Enum.at(products, rem(i * 2 + j, 1000)).id,
              name: "Captured item",
              unit_price: 500,
              quantity: 1,
              notes: "Synthetic"
            }
      end)

    for chunk <- Enum.chunk_every(lines, 500), do: OperatorRepo.insert_all(Line, chunk)
    %{date: date, session: hd(sessions).id, sessions: count, sales: count * 1000}
  end

  def read(actor, workflow, expected) do
    workspace = Instantflow.Operations.workspace(actor, expected.date, workflow)
    visit = Instantflow.Operations.visit(actor, expected.session, workflow)

    unless workspace.report.sales == expected.sales and
             workspace.report.settled_count == expected.sessions,
           do: raise("incorrect full operational totals")

    unless workspace.pagination.products.total == 1000 and
             workspace.pagination.resources.total == 1000,
           do: raise("incorrect supporting totals")

    unless length(workspace.products) == 25 and length(workspace.resources) == 25 and
             length(workspace.report.consumption) == 25,
           do: raise("unbounded operational projection")

    %{returned_rows: length(workspace.products), visit: visit}
  end
end

Instantflow.ReadBenchmark.run(Instantflow.SupportReadFixtures)
