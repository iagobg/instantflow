defmodule Instantflow.WorkflowRuntime do
  @moduledoc "Transactional guarded commands. Lock order: actor user, membership, workflow (create) or ticket, sections, receipt/outbox."
  import Ecto.Query
  alias Instantflow.{Identity, Repo, Tenant}
  alias Instantflow.WorkflowCatalog.{Definition, Version, Workflow}
  alias Instantflow.WorkflowRuntime.{Event, Guards, Policy, Receipt, Section, Ticket}
  alias Instantflow.Delivery.Message

  def command(actor, command) when is_map(command) do
    with :ok <- command_shape(command) do
      Tenant.transaction(actor, fn actor ->
        actor = Identity.lock_scope!(actor)
        digest = :crypto.hash(:sha256, :erlang.term_to_binary(command, [:deterministic]))

        receipt =
          Repo.get_by(Receipt,
            organization_id: actor.organization_id,
            actor_id: actor.user_id,
            operation: command["operation"],
            key: command["key"]
          )

        if receipt do
          ticket = Repo.get!(Ticket, receipt.ticket_id)
          version = Repo.get!(Version, ticket.workflow_version_id)
          unless Policy.discover?(actor, ticket, version), do: Repo.rollback(:forbidden)
          unless receipt.digest == digest, do: Repo.rollback(:idempotency_mismatch)
          receipt.result
        else
          ticket = apply_command(actor, command)
          result = %{"ticket_id" => ticket.id, "revision" => ticket.revision}

          Repo.insert!(%Receipt{
            organization_id: actor.organization_id,
            operation: command["operation"],
            actor_id: actor.user_id,
            key: command["key"],
            digest: digest,
            ticket_id: ticket.id,
            result: result
          })

          result
        end
      end)
    end
  end

  def command(_, _), do: {:error, :invalid_command}

  def get(actor, id), do: Tenant.read(actor, &get_scoped(&1, id), {:error, :not_found})

  defp get_scoped(actor, id) do
    with scope when not is_nil(scope) <- Identity.scope(actor.user_id, actor.organization_id),
         %Ticket{} = ticket <- Repo.get(Ticket, id),
         %Version{} = version <- Repo.get(Version, ticket.workflow_version_id),
         true <- Policy.discover?(scope, ticket, version) do
      sections = Repo.all(from s in Section, where: s.ticket_id == ^ticket.id, order_by: s.key)

      readable =
        Enum.filter(
          version.definition["sections"],
          &Policy.section?(scope, ticket, version, &1, :read)
        )

      keys = Enum.map(readable, & &1["key"])

      events =
        Repo.all(from e in Event, where: e.ticket_id == ^id, order_by: [desc: e.revision])
        |> Enum.filter(&Policy.history?(scope, ticket, version, &1))

      event_ids = Enum.map(events, & &1.id)

      projected_definition =
        version.definition
        |> Map.take(~w(name stages transitions))
        |> Map.put(
          "sections",
          Enum.map(readable, &Map.take(&1, ~w(key label classification fields)))
        )
        |> Map.update!("transitions", fn edges ->
          Enum.filter(edges, fn edge ->
            Policy.history?(scope, ticket, version, %{operation: edge["key"]})
          end)
          |> Enum.map(&Map.take(&1, ~w(key label from to kind)))
        end)

      {:ok,
       %{
         ticket: ticket,
         version: %{version | definition: projected_definition, bindings: %{}},
         sections: Enum.filter(sections, &(&1.key in keys)),
         section_definitions:
           Enum.map(readable, &Map.take(&1, ~w(key label classification fields))),
         can_retry: Policy.retry?(scope, ticket, version),
         editable:
           Enum.filter(readable, &Policy.section?(scope, ticket, version, &1, :edit))
           |> Enum.map(& &1["key"]),
         transitions:
           Enum.filter(
             version.definition["transitions"],
             &Policy.transition?(scope, ticket, version, &1)
           )
           |> Enum.map(&Map.take(&1, ~w(key label require_reason kind))),
         events: events,
         deliveries:
           Repo.all(
             from m in Message,
               where: m.ticket_id == ^id and m.kind != "refresh" and m.event_id in ^event_ids,
               order_by: m.id
           )
       }}
    else
      _ -> {:error, :not_found}
    end
  end

  def list(actor), do: Tenant.read(actor, &list_scoped/1, [])

  def search(actor, filters \\ %{}) do
    Tenant.read(
      actor,
      fn scope ->
        tickets = list_scoped(scope)
        counts = Enum.frequencies_by(tickets, & &1.stage)

        stage_labels =
          tickets
          |> Enum.flat_map(& &1.workflow_version.definition["stages"])
          |> Map.new(&{&1["key"], &1["label"]})

        stage = filters["stage"] || ""
        query = String.slice(to_string(filters["query"] || ""), 0, 100) |> String.downcase()

        filtered =
          Enum.filter(tickets, fn t ->
            (stage == "" or t.stage == stage) and
              (query == "" or
                 String.contains?(
                   String.downcase("#{t.id} #{t.workflow_version.definition["name"]}"),
                   query
                 ))
          end)

        page =
          case Integer.parse(to_string(filters["page"] || "1")) do
            {n, ""} when n > 0 -> min(n, max(1, ceil(length(filtered) / 25)))
            _ -> 1
          end

        %{
          tickets: Enum.slice(filtered, (page - 1) * 25, 25),
          total: length(tickets),
          filtered: length(filtered),
          counts: counts,
          stage_labels: stage_labels,
          page: page,
          pages: max(1, ceil(length(filtered) / 25))
        }
      end,
      %{tickets: [], total: 0, filtered: 0, counts: %{}, stage_labels: %{}, page: 1, pages: 1}
    )
  end

  def list_topic(scope),
    do: "organization:#{scope.organization_id}:user:#{scope.user_id}:requests"

  # Called by the tenant-bound outbox. Only authorized recipients get an invalidation,
  # without record IDs or payloads; each recipient independently reauthorizes its query.
  def invalidate_lists(organization_id, ticket_id) do
    ticket = Repo.get(Ticket, ticket_id)
    version = ticket && Repo.get(Version, ticket.workflow_version_id)

    if version do
      Repo.all(
        from m in Instantflow.Identity.Membership,
          where: m.organization_id == ^organization_id and m.active
      )
      |> Enum.each(fn member ->
        scope = Instantflow.Access.load(member)

        if Policy.discover?(scope, ticket, version),
          do: Phoenix.PubSub.broadcast(Instantflow.PubSub, list_topic(scope), :requests_changed)
      end)
    end
  end

  defp list_scoped(actor) do
    case Identity.scope(actor.user_id, actor.organization_id) do
      nil ->
        []

      scope ->
        Repo.all(
          from t in Ticket,
            where:
              t.organization_id == ^actor.organization_id and
                (t.requester_id == ^scope.user_id or
                   t.assigned_department_id in ^Enum.map(
                     Instantflow.Access.profiles(scope),
                     & &1.department_id
                   )),
            order_by: [desc: t.id],
            preload: [:workflow_version]
        )
        |> Enum.filter(&Policy.discover?(scope, &1, &1.workflow_version))
        |> Enum.map(fn ticket ->
          version = ticket.workflow_version

          %{
            ticket
            | workflow_version: %{
                version
                | bindings: %{},
                  definition: Map.take(version.definition, ~w(name stages))
              }
          }
        end)
    end
  end

  defp apply_command(actor, %{"operation" => "create"} = command) do
    workflow =
      Repo.one(
        from w in Workflow,
          where: w.id == ^command["workflow_id"] and w.organization_id == ^actor.organization_id,
          lock: "FOR UPDATE"
      )

    unless workflow, do: Repo.rollback(:not_found)

    version =
      Repo.one(
        from v in Version,
          where: v.workflow_id == ^workflow.id,
          order_by: [desc: v.number],
          limit: 1
      )

    unless version &&
             Enum.any?(
               version.definition["creation"]["roles"],
               &Instantflow.Access.role?(actor, version.bindings["roles"][&1])
             ),
           do: Repo.rollback(:forbidden)

    entry = Enum.find(version.definition["stages"], & &1["initial"])

    ticket =
      Repo.insert!(%Ticket{
        organization_id: actor.organization_id,
        workflow_id: workflow.id,
        workflow_version_id: version.id,
        requester_id: actor.user_id,
        stage: entry["key"],
        assigned_department_id:
          version.bindings["departments"][version.definition["assignment"]["department_binding"]]
      })

    for s <- version.definition["sections"],
        do:
          Repo.insert!(%Section{
            organization_id: actor.organization_id,
            ticket_id: ticket.id,
            key: s["key"]
          })

    record(ticket, actor, "create", nil, nil, [])
    ticket
  end

  defp apply_command(actor, command) do
    ticket =
      Repo.one(
        from t in Ticket,
          where: t.id == ^command["ticket_id"] and t.organization_id == ^actor.organization_id,
          lock: "FOR UPDATE"
      )

    unless ticket, do: Repo.rollback(:not_found)
    version = Repo.get!(Version, ticket.workflow_version_id)
    unless Policy.discover?(actor, ticket, version), do: Repo.rollback(:forbidden)

    sections =
      Repo.all(
        from s in Section, where: s.ticket_id == ^ticket.id, order_by: s.key, lock: "FOR UPDATE"
      )

    case command["operation"] do
      "save_section" -> save_section(actor, ticket, version, sections, command)
      "transition" -> transition(actor, ticket, version, sections, command)
    end
  end

  defp save_section(actor, ticket, version, sections, c) do
    section = Enum.find(sections, &(&1.key == c["section"]))
    definition = Enum.find(version.definition["sections"], &(&1["key"] == c["section"]))

    unless section && definition && Policy.section?(actor, ticket, version, definition, :edit),
      do: Repo.rollback(:forbidden)

    unless ticket.stage_revision == c["expected_stage_revision"] and
             section.revision == c["expected_section_revision"],
           do: Repo.rollback(:conflict)

    case Definition.validate_values(definition, c["values"]) do
      :ok -> :ok
      {:error, errors} -> Repo.rollback({:invalid_values, errors})
    end

    section
    |> Ecto.Changeset.change(values: c["values"], revision: section.revision + 1)
    |> Repo.update!()

    updated = ticket |> Ecto.Changeset.change(revision: ticket.revision + 1) |> Repo.update!()
    record(updated, actor, "save:" <> section.key, ticket.stage, nil, [])
    updated
  end

  defp transition(actor, ticket, version, sections, c) do
    transition = Enum.find(version.definition["transitions"], &(&1["key"] == c["transition"]))

    unless transition && Policy.transition?(actor, ticket, version, transition),
      do: Repo.rollback(:forbidden)

    readable_keys =
      version.definition["sections"]
      |> Enum.filter(&Policy.section?(actor, ticket, version, &1, :read))
      |> Enum.map(& &1["key"])

    revisions =
      sections |> Enum.filter(&(&1.key in readable_keys)) |> Map.new(&{&1.key, &1.revision})

    unless ticket.revision == c["expected_revision"] and revisions == c["section_revisions"],
      do: Repo.rollback(:conflict)

    reason = c["reason"]

    unless is_nil(reason) or (is_binary(reason) and String.length(reason) <= 2000),
      do: Repo.rollback(:invalid_reason)

    if transition["require_reason"] and not Definition.present?(reason),
      do: Repo.rollback(:reason_required)

    values =
      for s <- sections, {key, value} <- s.values, into: %{}, do: {s.key <> "." <> key, value}

    unless Enum.all?(transition["required_fields"], &Definition.present?(values[&1])),
      do: Repo.rollback(:required_fields)

    deliveries =
      Repo.all(
        from m in Message,
          where: m.ticket_id == ^ticket.id,
          distinct: m.kind,
          order_by: [asc: m.kind, desc: m.id]
      )
      |> Enum.filter(&(&1.status == "succeeded"))
      |> Enum.map(& &1.kind)

    unless Guards.pass?(
             transition["guard"],
             values,
             Definition.fields(version.definition),
             deliveries
           ),
           do: Repo.rollback(:guard_failed)

    if transition["kind"] == "resubmission" and ticket.return_stage != transition["to"],
      do: Repo.rollback(:invalid_return)

    return_stage =
      case transition["kind"] do
        "correction" -> ticket.stage
        "resubmission" -> nil
        _ -> ticket.return_stage
      end

    updated =
      ticket
      |> Ecto.Changeset.change(
        stage: transition["to"],
        return_stage: return_stage,
        revision: ticket.revision + 1,
        stage_revision: ticket.stage_revision + 1
      )
      |> Repo.update!()

    record(updated, actor, transition["key"], ticket.stage, reason, transition["actions"])
    updated
  end

  defp record(ticket, actor, operation, from_stage, reason, actions) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended('outbox:' || $1::text, 0))", [
      to_string(actor.organization_id)
    ])

    queued =
      Repo.aggregate(
        from(m in Message,
          where: m.organization_id == ^actor.organization_id and m.status == "pending"
        ),
        :count
      )

    if queued + length(actions) + 1 >
         Application.get_env(:instantflow, :max_pending_deliveries_per_organization, 1000),
       do: Repo.rollback(:queue_full)

    event =
      Repo.insert!(%Event{
        organization_id: actor.organization_id,
        ticket_id: ticket.id,
        actor_id: actor.user_id,
        operation: operation,
        from_stage: from_stage,
        to_stage: ticket.stage,
        reason: reason,
        revision: ticket.revision
      })

    for {action, index} <-
          Enum.with_index([%{"type" => "refresh", "behavior" => "success"} | actions]) do
      Repo.insert!(%Message{
        organization_id: actor.organization_id,
        ticket_id: ticket.id,
        event_id: event.id,
        key: "event:#{event.id}:#{index}",
        kind: action["type"],
        behavior: action["behavior"]
      })
    end
  end

  defp command_shape(c) do
    allowed =
      case c["operation"] do
        "create" ->
          ~w(operation key workflow_id)

        "save_section" ->
          ~w(operation key ticket_id section values expected_stage_revision expected_section_revision)

        "transition" ->
          ~w(operation key ticket_id transition expected_revision section_revisions reason)

        _ ->
          []
      end

    required = allowed -- ["reason"]

    valid =
      allowed != [] and Enum.all?(Map.keys(c), &(&1 in allowed)) and
        Enum.all?(required, &Map.has_key?(c, &1)) and
        is_binary(c["key"]) and byte_size(c["key"]) in 1..128 and
        Enum.all?(
          Enum.filter(
            required,
            &(&1 in ~w(workflow_id ticket_id expected_stage_revision expected_section_revision expected_revision))
          ),
          &(is_integer(c[&1]) and c[&1] > 0 and c[&1] < 9_223_372_036_854_775_807)
        )

    if valid, do: :ok, else: {:error, :invalid_command}
  end
end
