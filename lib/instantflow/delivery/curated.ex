defmodule Instantflow.Delivery.Curated do
  @moduledoc "Curated immutable snapshots in the existing durable outbox, with live eligibility fencing."
  import Ecto.Query
  alias Instantflow.{Access, Identity, Repo, Tenant, WorkflowRuntime}
  alias Instantflow.Delivery.Message
  alias Instantflow.Participants.Relationship
  alias Instantflow.WorkflowCatalog.{Communications, Definition, Version}
  alias Instantflow.WorkflowRuntime.{Policy, Receipt, Section, Ticket}

  def authorized?(scope, ticket, version, spec) do
    spec && Enum.any?(spec["release_actors"], &Policy.actor?(scope, ticket, version, &1)) &&
      Enum.all?(spec["fields"], fn ref ->
        section =
          Enum.find(version.definition["sections"], &(&1["key"] == hd(String.split(ref, "."))))

        section && Policy.section?(scope, ticket, version, section, :read)
      end)
  end

  def release(actor, ticket_id, key, recipient_id, revision, receipt_key) do
    Tenant.transaction(actor, fn scope ->
      unless is_integer(ticket_id) and is_integer(recipient_id) and is_integer(revision) and
               is_binary(key),
             do: Repo.rollback(:invalid_command)

      ticket =
        Repo.one(from t in Ticket, where: t.id == ^ticket_id, lock: "FOR UPDATE") ||
          Repo.rollback(:not_found)

      version = Repo.get!(Version, ticket.workflow_version_id)
      spec = Communications.find(version.definition, key)
      unless authorized?(scope, ticket, version, spec), do: Repo.rollback(:forbidden)

      relationship =
        Repo.get_by(Relationship,
          ticket_id: ticket.id,
          membership_id: recipient_id,
          relationship: spec["recipient_relationship"],
          status: "verified"
        )

      unless relationship && relationship.verified_at && recipient?(version, relationship),
        do: Repo.rollback(:ineligible_recipient)

      unless is_binary(receipt_key) and byte_size(receipt_key) in 1..128,
        do: Repo.rollback(:invalid_command)

      digest =
        :crypto.hash(
          :sha256,
          :erlang.term_to_binary({ticket_id, key, recipient_id, revision}, [:deterministic])
        )

      receipt =
        Repo.get_by(Receipt,
          organization_id: scope.organization_id,
          actor_id: scope.user_id,
          operation: "curated_release",
          key: receipt_key
        )

      if receipt do
        unless receipt.digest == digest, do: Repo.rollback(:idempotency_mismatch)
        receipt.result
      else
        unless ticket.revision == revision, do: Repo.rollback(:conflict)
        keys = spec["fields"] |> Enum.map(&(String.split(&1, ".") |> hd())) |> Enum.uniq()

        sections =
          Repo.all(
            from s in Section, where: s.ticket_id == ^ticket.id and s.key in ^keys, limit: 100
          )
          |> Map.new(&{&1.key, &1.values})

        content =
          Enum.map(spec["fields"], fn ref ->
            [section, field] = String.split(ref, ".")
            value = (sections[section] || %{})[field]
            unless Definition.present?(value), do: Repo.rollback(:required_fields)
            %{"label" => Definition.fields(version.definition)[ref]["label"], "value" => value}
          end)

        updated = ticket |> Ecto.Changeset.change(revision: ticket.revision + 1) |> Repo.update!()
        event = WorkflowRuntime.record(updated, scope, "release:" <> key, ticket.stage, nil, [])
        pending = Repo.aggregate(from(m in Message, where: m.status == "pending"), :count)

        if pending + 1 >
             Application.get_env(:instantflow, :max_pending_deliveries_per_organization, 1000),
           do: Repo.rollback(:queue_full)

        message =
          Repo.insert!(%Message{
            organization_id: scope.organization_id,
            ticket_id: ticket.id,
            event_id: event.id,
            key: "curated:#{event.id}",
            kind: "simulate_notification",
            behavior: if(spec["behavior"] == "ambiguous", do: "failure", else: spec["behavior"]),
            recipient_membership_id: recipient_id,
            authorized_membership_id: scope.id,
            payload: %{
              "release" => key,
              "version_id" => version.id,
              "label" => spec["label"],
              "relationship_id" => relationship.id,
              "relationship_revision" => relationship.revision,
              "content" => content,
              "ambiguous" => spec["behavior"] == "ambiguous"
            }
          })

        value = %{
          "message_id" => message.id,
          "ticket_id" => ticket.id,
          "revision" => updated.revision
        }

        Repo.insert!(%Receipt{
          organization_id: scope.organization_id,
          actor_id: scope.user_id,
          operation: "curated_release",
          key: receipt_key,
          digest: digest,
          ticket_id: ticket.id,
          result: value
        })

        value
      end
    end)
  end

  @doc "Called only while holding the shared tenant authorization gate."
  def eligible?(message) do
    ticket = Repo.get(Ticket, message.ticket_id)
    version = ticket && Repo.get(Version, ticket.workflow_version_id)

    relationship =
      Repo.get_by(Relationship,
        id: message.payload["relationship_id"],
        ticket_id: message.ticket_id,
        membership_id: message.recipient_membership_id
      )

    member = Repo.get(Instantflow.Identity.Membership, message.authorized_membership_id)
    author = member && Identity.scope(member.user_id, message.organization_id)
    spec = version && Communications.find(version.definition, message.payload["release"])

    not is_nil(version) and version.id == message.payload["version_id"] and
      not is_nil(relationship) and relationship.status == "verified" and
      not is_nil(relationship.verified_at) and
      relationship.revision == message.payload["relationship_revision"] and
      spec != nil and relationship.relationship == spec["recipient_relationship"] and
      recipient?(version, relationship) and
      author != nil and author.id == message.authorized_membership_id and
      authorized?(author, ticket, version, spec)
  end

  def retry(actor, id), do: mutate(actor, id, "retry", nil)

  def resolve(actor, id, outcome, reason) when outcome in ~w(succeeded failed),
    do: mutate(actor, id, outcome, reason)

  def resolve(_, _, _, _), do: {:error, :invalid_command}

  defp mutate(actor, id, operation, reason) do
    Tenant.transaction(actor, fn scope ->
      message = Repo.get(Message, id) || Repo.rollback(:not_found)
      ticket = Repo.one!(from t in Ticket, where: t.id == ^message.ticket_id, lock: "FOR UPDATE")
      message = Repo.one!(from m in Message, where: m.id == ^id, lock: "FOR UPDATE")
      version = Repo.get!(Version, ticket.workflow_version_id)
      spec = Communications.find(version.definition, message.payload["release"])

      unless authorized?(scope, ticket, version, spec) and eligible?(message),
        do: Repo.rollback(:forbidden)

      if operation == "retry" do
        unless message.status == "failed", do: Repo.rollback(:not_failed)
        if message.attempts >= 3, do: Repo.rollback(:retry_limit)

        Repo.update!(
          Ecto.Changeset.change(message, status: "pending", retried_by_id: scope.user_id)
        )
      else
        unless message.status == "ambiguous" and is_binary(reason) and
                 String.length(String.trim(reason)) in 1..2000,
               do: Repo.rollback(:invalid_state)

        number = message.attempts + 1

        Repo.insert!(%Instantflow.Delivery.Attempt{
          organization_id: scope.organization_id,
          outbox_message_id: message.id,
          number: number,
          result: "resolved_" <> operation,
          actor_id: scope.user_id
        })

        updated = ticket |> Ecto.Changeset.change(revision: ticket.revision + 1) |> Repo.update!()

        WorkflowRuntime.record(
          updated,
          scope,
          "release:" <> spec["key"],
          ticket.stage,
          reason,
          []
        )

        Repo.update!(
          Ecto.Changeset.change(message,
            status: operation,
            attempts: number,
            retried_by_id: scope.user_id
          )
        )
      end
    end)
  end

  def controls(scope, ticket, version, search \\ "") do
    search = if is_binary(search), do: String.slice(search, 0, 100), else: ""

    for spec <- Communications.specs(version.definition),
        authorized?(scope, ticket, version, spec) do
      recipients =
        Repo.all(
          from [r, m, u] in recipient_query(version, spec["recipient_relationship"]),
            where:
              r.ticket_id == ^ticket.id and
                fragment("strpos(lower(?), lower(?)) > 0", u.name, ^search),
            distinct: m.id,
            order_by: m.id,
            limit: 25,
            select: {u.name, m.id}
        )

      message =
        Repo.one(
          from m in Message,
            where:
              m.ticket_id == ^ticket.id and fragment("?->>'release' = ?", m.payload, ^spec["key"]),
            order_by: [desc: m.id],
            limit: 1
        )

      %{
        id: spec["key"],
        key: spec["key"],
        label: spec["label"],
        recipients: recipients,
        message:
          message &&
            %{
              id: message.id,
              status: message.status,
              retry?: message.status == "failed" and message.attempts < 3,
              resolve?: message.status == "ambiguous"
            }
      }
    end
  end

  def controls_for(actor, id, search \\ "") do
    Tenant.read(
      actor,
      fn scope ->
        ticket = Repo.get(Ticket, id) || Repo.rollback(:not_found)
        controls(scope, ticket, Repo.get!(Version, ticket.workflow_version_id), search)
      end,
      []
    )
  end

  def successes(ticket, version) do
    if Communications.specs(version.definition) == [] do
      []
    else
      Repo.all(
        from m in Message,
          where: m.ticket_id == ^ticket.id and fragment("jsonb_exists(?, 'release')", m.payload),
          distinct: fragment("?->>'release'", m.payload),
          order_by: [asc: fragment("?->>'release'", m.payload), desc: m.id],
          limit: 20
      )
      |> Enum.filter(&(&1.status == "succeeded" and eligible?(&1)))
      |> Enum.map(&("communication:" <> &1.payload["release"]))
    end
  end

  def inbox(actor, workflow_id, params \\ %{}) do
    Tenant.read(
      actor,
      fn scope ->
        query = inbox_query(scope, workflow_id)

        query =
          if is_integer(params["ticket_id"]),
            do: where(query, [message: m], m.ticket_id == ^params["ticket_id"]),
            else: query

        query =
          if is_list(params["keys"]),
            do:
              where(query, [message: m], fragment("?->>'release'", m.payload) in ^params["keys"]),
            else: query

        total = Repo.aggregate(query, :count)
        pages = max(1, ceil(total / 25))

        page =
          case Integer.parse(if(is_binary(params["page"]), do: params["page"], else: "1")) do
            {n, ""} when n > 0 -> min(n, pages)
            _ -> 1
          end

        rows =
          Repo.all(
            from [message: m] in query,
              order_by: [desc: m.id],
              limit: 25,
              offset: ^((page - 1) * 25),
              select: %{id: m.id, status: m.status, payload: m.payload}
          )
          |> Enum.map(fn row ->
            %{
              id: row.id,
              label: row.payload["label"],
              status: row.status,
              content: if(row.status == "succeeded", do: row.payload["content"], else: [])
            }
          end)

        %{rows: rows, total: total, page: page, pages: pages}
      end,
      %{rows: [], total: 0, page: 1, pages: 1}
    )
  end

  def options(actor) do
    Tenant.read(
      actor,
      fn scope ->
        Repo.all(
          from [ticket: t] in inbox_query(scope, nil),
            distinct: t.workflow_id,
            order_by: t.workflow_id,
            limit: 100,
            select: t.workflow_id
        )
        |> Enum.map(&%{id: &1, label: "Mensagens compartilhadas"})
      end,
      []
    )
  end

  def invalidate(ticket_id) do
    ids =
      Repo.all(
        from m in Message,
          join: member in Instantflow.Identity.Membership,
          on: member.id == m.recipient_membership_id,
          where: m.ticket_id == ^ticket_id,
          distinct: member.user_id,
          limit: 100,
          select: {member.organization_id, member.user_id}
      )

    Enum.each(ids, fn {org, user} ->
      Phoenix.PubSub.broadcast(
        Instantflow.PubSub,
        "organization:#{org}:user:#{user}",
        :communications_changed
      )
    end)
  end

  defp inbox_query(scope, workflow_id) do
    versions =
      Repo.all(
        from v in Version, where: fragment("jsonb_exists(?, 'communications')", v.definition)
      )

    rule =
      Enum.reduce(versions, dynamic(false), fn version, acc ->
        Enum.reduce(Communications.specs(version.definition), acc, fn spec, acc ->
          roles = candidate_roles(version, spec["recipient_relationship"])

          if Access.role?(scope, roles) do
            dynamic(
              [message: m, ticket: t, relationship: r],
              ^acc or
                (t.workflow_version_id == ^version.id and
                   r.relationship == ^spec["recipient_relationship"] and
                   fragment("?->>'release' = ?", m.payload, ^spec["key"]))
            )
          else
            acc
          end
        end)
      end)

    query =
      from m in Message,
        as: :message,
        join: t in Ticket,
        as: :ticket,
        on: t.id == m.ticket_id,
        join: r in Relationship,
        as: :relationship,
        on:
          r.ticket_id == t.id and r.workflow_id == t.workflow_id and
            r.membership_id == m.recipient_membership_id,
        where:
          m.organization_id == ^scope.organization_id and m.recipient_membership_id == ^scope.id,
        where: r.status == "verified" and not is_nil(r.verified_at),
        where:
          fragment(
            "?::text = ?->>'relationship_id' AND ?::text = ?->>'relationship_revision' AND ?::text = ?->>'version_id'",
            r.id,
            m.payload,
            r.revision,
            m.payload,
            t.workflow_version_id,
            m.payload
          ),
        where: ^rule

    if is_integer(workflow_id),
      do: where(query, [ticket: t], t.workflow_id == ^workflow_id),
      else: query
  end

  defp recipient?(version, relationship),
    do:
      Repo.exists?(
        where(recipient_query(version, relationship.relationship), [r], r.id == ^relationship.id)
      )

  defp recipient_query(version, key) do
    roles = candidate_roles(version, key)

    from r in Relationship,
      join: m in Instantflow.Identity.Membership,
      on: m.id == r.membership_id,
      join: u in Instantflow.Identity.User,
      on: u.id == m.user_id,
      left_join: g in Instantflow.Access.Grant,
      on: g.membership_id == m.id and g.organization_id == m.organization_id,
      where:
        r.workflow_id == ^version.workflow_id and r.organization_id == ^version.organization_id and
          r.relationship == ^key and
          r.status == "verified" and not is_nil(r.verified_at) and m.active and u.active and
          (m.role in ^roles or g.role in ^roles)
  end

  defp candidate_roles(version, key) do
    spec = Enum.find(Map.get(version.definition, "participants", []), &(&1["key"] == key))

    if spec,
      do:
        Enum.flat_map(spec["candidate_roles"] || [], &Map.get(version.bindings["roles"], &1, []))
        |> Enum.uniq(),
      else: []
  end
end
