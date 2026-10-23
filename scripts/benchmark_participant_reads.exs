System.put_env("READ_BENCHMARK_LIBRARY", "true")
Code.require_file("benchmark_reads.exs", __DIR__)
Code.require_file("../test/support/builder_fixtures.ex", __DIR__)

defmodule Instantflow.ParticipantReadFixtures do
  @moduledoc false
  alias Instantflow.{OperatorRepo, Identity, BuilderFixtures}
  alias Instantflow.Identity.{Organization, Department, Membership, User}
  alias Instantflow.WorkflowCatalog.{Workflow, Version, Definition}
  alias Instantflow.WorkflowRuntime.{Ticket, Section, Event, Projections}
  alias Instantflow.Participants.Relationship
  alias Instantflow.Delivery.{Message, Curated}

  def surface, do: System.get_env("READ_SURFACE", "participants")

  def prepare do
    for table <- ~w(tickets workflow_versions ticket_sections ticket_participants outbox_messages),
        do: OperatorRepo.query!("ANALYZE " <> table)
  end

  def populate(index, hash, d) do
    org =
      OperatorRepo.insert!(%Organization{
        slug: "participant-read-#{index}",
        name: "Synthetic participant #{index}"
      })

    dep = OperatorRepo.insert!(%Department{organization_id: org.id, name: "Local team"})

    members =
      for n <- 1..5 do
        user =
          OperatorRepo.insert!(%User{
            email: "participant-#{index}-#{n}@example.invalid",
            name: "Synthetic external",
            password_hash: hash
          })

        OperatorRepo.insert!(%Membership{
          organization_id: org.id,
          department_id: dep.id,
          user_id: user.id,
          role: "external"
        })
      end

    first = hd(members)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    processes =
      for n <- 1..d.processes do
        key = "participant_read_#{n}"
        definition = definition(key)
        :ok = Definition.validate(definition)

        workflow =
          OperatorRepo.insert!(%Workflow{
            organization_id: org.id,
            key: key,
            name: definition["name"]
          })

        {_, versions} =
          OperatorRepo.insert_all(
            Version,
            for(
              v <- 1..d.versions,
              do: %{
                organization_id: org.id,
                workflow_id: workflow.id,
                number: v,
                definition: put_in(definition, ["stages", Access.at(0), "label"], "Pinned #{v}"),
                bindings: %{
                  "roles" => %{
                    "requester" => ["external"],
                    "reviewer" => ["admin"],
                    "visitor" => ["external"]
                  },
                  "departments" => %{"responsible" => dep.id}
                },
                published_by_id: first.user_id,
                inserted_at: now,
                updated_at: now
              }
            ),
            returning: [:id, :number]
          )

        {workflow, Enum.sort_by(versions, & &1.number)}
      end

    count =
      case d.shape do
        "equal" -> 1000
        "uneven" when index == 1 -> 7000
        "uneven" when index <= 4 -> 334
        "uneven" -> 333
      end

    rows =
      for n <- 1..count do
        {workflow, versions} = Enum.at(processes, rem(n - 1, d.processes))
        version = Enum.at(versions, rem(div(n - 1, d.processes), d.used_versions))

        %{
          organization_id: org.id,
          workflow_id: workflow.id,
          workflow_version_id: version.id,
          requester_id: first.user_id,
          assigned_department_id: dep.id,
          stage: "draft",
          revision: 1,
          stage_revision: 1,
          inserted_at: now,
          updated_at: now
        }
      end

    tickets = insert(Ticket, rows, [:id, :workflow_id, :workflow_version_id])

    insert(
      Section,
      Enum.map(
        tickets,
        &%{
          organization_id: org.id,
          ticket_id: &1.id,
          key: "customer_details",
          values: %{"description" => String.duplicate("p", 1024)},
          revision: 1,
          inserted_at: now,
          updated_at: now
        }
      ),
      false
    )

    visible =
      tickets
      |> Enum.with_index()
      |> Enum.filter(fn {_, i} -> rem(i, d.hidden + 1) == 0 end)
      |> Enum.map(&elem(&1, 0))

    relationships =
      insert(
        Relationship,
        for(
          ticket <- visible,
          member <- members,
          do: %{
            organization_id: org.id,
            workflow_id: ticket.workflow_id,
            ticket_id: ticket.id,
            membership_id: member.id,
            relationship: "claimant",
            status: "verified",
            revision: 2,
            verified_at: now,
            verified_by_id: first.user_id,
            inserted_at: now,
            updated_at: now
          }
        ),
        [:id, :ticket_id, :membership_id]
      )

    events =
      insert(
        Event,
        Enum.map(
          visible,
          &%{
            organization_id: org.id,
            ticket_id: &1.id,
            actor_id: first.user_id,
            operation: "release:read_notice",
            from_stage: "draft",
            to_stage: "draft",
            revision: 1,
            inserted_at: now,
            updated_at: now
          }
        ),
        [:id, :ticket_id]
      )
      |> Map.new(&{&1.ticket_id, &1.id})

    pins = Map.new(tickets, &{&1.id, &1.workflow_version_id})

    insert(
      Message,
      Enum.map(relationships, fn rel ->
        %{
          organization_id: org.id,
          ticket_id: rel.ticket_id,
          event_id: events[rel.ticket_id],
          recipient_membership_id: rel.membership_id,
          authorized_membership_id: first.id,
          key: "curated:#{rel.id}",
          kind: "simulate_notification",
          behavior: "success",
          status: "succeeded",
          attempts: 1,
          payload: %{
            "release" => "read_notice",
            "version_id" => pins[rel.ticket_id],
            "label" => "Synthetic result",
            "relationship_id" => rel.id,
            "relationship_revision" => 2,
            "content" => [%{"label" => "Description", "value" => String.duplicate("p", 1024)}]
          },
          inserted_at: now,
          updated_at: now
        }
      end),
      false
    )

    {workflow, _} = hd(processes)

    expected = %{
      process: Enum.count(visible, &(&1.workflow_id == workflow.id)),
      discovery: visible |> Enum.map(& &1.workflow_id) |> Enum.uniq() |> length(),
      surface: d.surface
    }

    Enum.map(members, &{Identity.scope(&1.user_id, org.id), workflow.id, expected})
  end

  def read(actor, workflow, expected) do
    {discovery, page} =
      case expected.surface do
        "participants" ->
          {Projections.participant_discovery(actor),
           Projections.participant_search(actor, workflow, "my_packet")}

        "messages" ->
          {Curated.discovery(actor), Curated.inbox(actor, workflow)}
      end

    unless discovery.total == expected.discovery and page.total == expected.process,
      do: raise("incorrect authorized participant/message count")

    unless length(discovery.rows) <= 25 and length(page.rows) <= 25,
      do: raise("unbounded participant/message page")

    %{returned_rows: length(page.rows)}
  end

  defp definition(key) do
    BuilderFixtures.participant_page_definition()
    |> Map.put("template_key", key)
    |> Map.put("name", "Independent participant " <> key)
    |> Map.update!("capabilities", &(&1 ++ ["communications"]))
    |> Map.put("communications", [
      %{
        "key" => "read_notice",
        "label" => "Synthetic notice",
        "recipient_relationship" => "claimant",
        "fields" => ["customer_details.description"],
        "release_actors" => [
          %{
            "role" => "reviewer",
            "scope" => "workflow_department",
            "department_binding" => "responsible"
          }
        ],
        "behavior" => "success"
      }
    ])
    |> update_in(["interface", "pages", Access.at(1), "participant", "messages"], fn _ ->
      ["read_notice"]
    end)
  end

  defp insert(schema, rows, returning),
    do:
      rows
      |> Enum.chunk_every(200)
      |> Enum.flat_map(fn chunk ->
        {_, inserted} = OperatorRepo.insert_all(schema, chunk, returning: returning)
        inserted || []
      end)
end

Instantflow.ReadBenchmark.run(Instantflow.ParticipantReadFixtures)
