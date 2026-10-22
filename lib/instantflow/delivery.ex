defmodule Instantflow.Delivery do
  @moduledoc "Organization-bound polling, bounded per tenant; suspension and finalization serialize on the organization lock."
  import Ecto.Query
  alias Instantflow.{Repo, Tenant, WorkflowRuntime}
  alias Instantflow.Delivery.{Attempt, Message}
  alias Instantflow.WorkflowRuntime.Ticket

  def pending_ids(organization_id) do
    case Tenant.raw(organization_id, fn ->
           Repo.all(
             from m in Message,
               where: m.organization_id == ^organization_id and m.status == "pending",
               order_by: m.id,
               limit: ^Application.get_env(:instantflow, :delivery_batch_per_organization, 20),
               select: m.id
           )
         end) do
      {:ok, ids} -> ids
      _ -> []
    end
  end

  def process(organization_id, id) do
    Tenant.raw(organization_id, fn ->
      Tenant.authorization_gate!(organization_id)
      message = Repo.get_by(Message, id: id, organization_id: organization_id)

      if message do
        # Match retry/command lock order: organization, ticket, outbox row.
        Repo.one!(from t in Ticket, where: t.id == ^message.ticket_id, lock: "FOR UPDATE")
        message = Repo.one(from m in Message, where: m.id == ^id, lock: "FOR UPDATE")
        apply_message!(organization_id, message)
      else
        :already_processed
      end
    end)
  end

  defp apply_message!(organization_id, message) do
    if message && message.status == "pending" do
      if message.kind == "refresh", do: refresh!(organization_id, message)
      number = message.attempts + 1

      result =
        cond do
          message.payload["release"] && not Instantflow.Delivery.Curated.eligible?(message) ->
            "cancelled"

          message.payload["ambiguous"] ->
            "ambiguous"

          message.behavior == "failure" or (message.behavior == "fail_once" and number == 1) ->
            "failed"

          true ->
            "succeeded"
        end

      Repo.insert!(%Attempt{
        organization_id: organization_id,
        outbox_message_id: message.id,
        number: number,
        result: result,
        actor_id: message.retried_by_id
      })

      if message.kind != "refresh",
        do:
          Repo.insert!(%Message{
            organization_id: organization_id,
            ticket_id: message.ticket_id,
            event_id: message.event_id,
            key: "delivery-result:#{message.id}:#{number}",
            kind: "refresh"
          })

      Repo.update!(Ecto.Changeset.change(message, status: result, attempts: number))
    else
      :already_processed
    end
  end

  defp process_batch(_organization_id, []), do: {:ok, 0}

  defp process_batch(organization_id, ids) do
    Tenant.raw(organization_id, fn ->
      Tenant.authorization_gate!(organization_id)

      ticket_ids =
        Repo.all(from m in Message, where: m.id in ^ids, select: m.ticket_id, distinct: true)

      tickets =
        Repo.all(from t in Ticket, where: t.id in ^ticket_ids, order_by: t.id, lock: "FOR UPDATE")
        |> Map.new(&{&1.id, &1})

      messages =
        Repo.all(
          from m in Message,
            where: m.id in ^ids and m.status == "pending",
            order_by: m.id,
            lock: "FOR UPDATE"
        )

      {refreshes, other} =
        Enum.split_with(
          messages,
          &(&1.kind == "refresh" and &1.behavior == "success" and
              String.starts_with?(&1.key, "event:"))
        )

      # Keep the selected per-organization bound, one immutable attempt per intent, and
      # one authorization/broadcast pass per ticket, without repeated transaction setup.
      refreshes
      |> Enum.group_by(& &1.ticket_id)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.each(fn {id, group} ->
        refresh!(organization_id, hd(group), Map.fetch!(tickets, id))
      end)

      if refreshes != [] do
        now = DateTime.utc_now(:second)

        attempts =
          Enum.map(
            refreshes,
            &%{
              organization_id: organization_id,
              outbox_message_id: &1.id,
              number: &1.attempts + 1,
              result: "succeeded",
              actor_id: &1.retried_by_id,
              inserted_at: now,
              updated_at: now
            }
          )

        Repo.insert_all(Attempt, attempts)
        refresh_ids = Enum.map(refreshes, & &1.id)

        Repo.update_all(from(m in Message, where: m.id in ^refresh_ids),
          set: [status: "succeeded", updated_at: now],
          inc: [attempts: 1]
        )
      end

      Enum.each(other, &apply_message!(organization_id, &1))
      length(messages)
    end)
  end

  # Business bursts may have several intents for the same committed revision. Persist
  # a checkpoint with attempt status, so a crash before commit retries the invalidation.
  # Delivery outcomes change without changing the ticket revision and must always notify.
  defp refresh!(organization_id, message) do
    ticket = Repo.one!(from t in Ticket, where: t.id == ^message.ticket_id, lock: "FOR UPDATE")
    refresh!(organization_id, message, ticket)
  end

  defp refresh!(organization_id, message, ticket) do
    outcome? = String.starts_with?(message.key, "delivery-result:")

    if outcome? or ticket.revision > ticket.refreshed_revision do
      WorkflowRuntime.invalidate_lists(organization_id, message.ticket_id)
      Instantflow.Delivery.Curated.invalidate(message.ticket_id)

      Phoenix.PubSub.broadcast(
        Instantflow.PubSub,
        topic(organization_id, message.ticket_id),
        {:ticket_changed, organization_id, message.ticket_id}
      )

      ticket |> Ecto.Changeset.change(refreshed_revision: ticket.revision) |> Repo.update!()
    end
  end

  def drain do
    %{rows: rows} = Repo.query!("SELECT id FROM dispatch_organizations()")

    # Each organization receives one bounded batch each pass, irrespective of the preceding tenant's backlog.
    Enum.map(rows, fn [id] ->
      Instantflow.PrivateDocuments.purge_expired(id)
      Instantflow.Calculations.purge_expired(id)
      {id, process_batch(id, pending_ids(id))}
    end)
  end

  def retry(actor, id) do
    curated? =
      Tenant.read(
        actor,
        fn _ ->
          message = Repo.get(Message, id)
          message && message.payload["release"]
        end,
        false
      )

    if curated?, do: Instantflow.Delivery.Curated.retry(actor, id), else: legacy_retry(actor, id)
  end

  defp legacy_retry(actor, id) do
    Tenant.transaction(actor, fn actor ->
      message = Repo.get_by(Message, id: id, organization_id: actor.organization_id)
      unless message, do: Repo.rollback(:not_found)

      ticket =
        Repo.one!(
          from t in Ticket,
            where: t.id == ^message.ticket_id and t.organization_id == ^actor.organization_id,
            lock: "FOR UPDATE"
        )

      case WorkflowRuntime.get(actor, ticket.id) do
        {:ok, data} ->
          unless data.can_retry && Enum.any?(data.deliveries, &(&1.id == id)),
            do: Repo.rollback(:forbidden)

        _ ->
          Repo.rollback(:forbidden)
      end

      message =
        Repo.one!(
          from m in Message,
            where: m.id == ^id and m.organization_id == ^actor.organization_id,
            lock: "FOR UPDATE"
        )

      unless message.status == "failed", do: Repo.rollback(:not_failed)

      Repo.update!(
        Ecto.Changeset.change(message, status: "pending", retried_by_id: actor.user_id)
      )
    end)
  end

  def topic(organization_id, id), do: "organization:#{organization_id}:ticket:#{id}"
end
