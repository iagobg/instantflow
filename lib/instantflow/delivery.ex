defmodule Instantflow.Delivery do
  @moduledoc "Organization-bound polling, bounded per tenant; suspension and finalization serialize on the organization lock."
  import Ecto.Query
  alias Instantflow.{Repo, Tenant}
  alias Instantflow.Delivery.{Attempt, Message}
  alias Instantflow.WorkflowRuntime.{Notifications, Ticket}
  require Logger

  def pending_ids(organization_id) do
    case Tenant.raw(organization_id, fn -> pending_ids!(organization_id) end) do
      {:ok, ids} -> ids
      _ -> []
    end
  end

  defp pending_ids!(organization_id) do
    Repo.all(
      from m in Message,
        where: m.organization_id == ^organization_id and m.status == "pending",
        order_by: m.id,
        limit: ^Application.get_env(:instantflow, :delivery_batch_per_organization, 20),
        select: m.id
    )
  end

  def process(organization_id, id) do
    Tenant.raw(organization_id, fn ->
      Tenant.authorization_gate!(organization_id)
      message = Repo.get_by(Message, id: id, organization_id: organization_id)

      if message do
        # Match retry/command lock order: organization, ticket, outbox row.
        ticket =
          Repo.one!(from t in Ticket, where: t.id == ^message.ticket_id, lock: "FOR UPDATE")

        message = Repo.one(from m in Message, where: m.id == ^id, lock: "FOR UPDATE")

        if message && message.status == "pending" do
          result = apply_message!(organization_id, message)
          refresh_batch!(organization_id, [message], %{ticket.id => ticket})
          result
        else
          :already_processed
        end
      else
        :already_processed
      end
    end)
  end

  defp apply_message!(organization_id, message) do
    if message && message.status == "pending" do
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

  defp process_batch(organization_id) do
    Tenant.raw(organization_id, fn ->
      process_messages!(organization_id, pending_ids!(organization_id))
    end)
  end

  defp process_messages!(_organization_id, []), do: 0

  defp process_messages!(organization_id, ids) do
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
    refresh_batch!(organization_id, messages, tickets)
    length(messages)
  end

  # Business bursts may have several intents for the same committed revision. Persist
  # a checkpoint with attempt status, so a crash before commit retries the invalidation.
  # Delivery outcomes change without changing the ticket revision and must always notify.
  defp refresh_batch!(organization_id, messages, tickets) do
    ids =
      messages
      |> Enum.filter(fn message ->
        ticket = Map.fetch!(tickets, message.ticket_id)

        message.kind == "refresh" and
          (String.starts_with?(message.key, "delivery-result:") or
             ticket.revision > ticket.refreshed_revision)
      end)
      |> Enum.map(& &1.ticket_id)
      |> Enum.uniq()
      |> Enum.sort()

    Notifications.invalidate_recipients(organization_id, ids)

    for id <- ids do
      Phoenix.PubSub.broadcast(
        Instantflow.PubSub,
        topic(organization_id, id),
        {:ticket_changed, organization_id, id}
      )
    end

    advanced =
      Enum.filter(ids, fn id ->
        ticket = Map.fetch!(tickets, id)
        ticket.revision > ticket.refreshed_revision
      end)

    if advanced != [] do
      now = DateTime.utc_now(:second)

      Repo.update_all(
        from(t in Ticket,
          where: t.id in ^advanced,
          update: [set: [refreshed_revision: t.revision, updated_at: ^now]]
        ),
        []
      )
    end
  end

  @doc "Process one bounded page. Repeated schedulers should retain drain_page/1's cursor."
  def drain, do: drain_page().results

  def drain_page(cursor \\ 0) when is_integer(cursor) and cursor >= 0 do
    started = System.monotonic_time()
    limit = Application.get_env(:instantflow, :delivery_organizations_per_pass, 50)

    %{rows: rows} =
      Repo.query!("SELECT id FROM public.delivery_organizations($1, $2)", [cursor, limit])

    results =
      Enum.map(rows, fn [id] ->
        # A failed tenant must not prevent progress for the rest of this page.
        result =
          try do
            process_batch(id)
          rescue
            _ ->
              Logger.warning("outbox_tenant_failed")
              {:error, :dispatch_failed}
          end

        {id, result}
      end)

    :telemetry.execute(
      [:instantflow, :delivery, :pass],
      %{
        duration: System.monotonic_time() - started,
        organizations: length(rows),
        failures: Enum.count(results, fn {_, result} -> match?({:error, _}, result) end)
      },
      %{}
    )

    %{cursor: if(rows == [], do: 0, else: rows |> List.last() |> hd()), results: results}
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

    if curated?,
      do: Instantflow.Delivery.Curated.retry(actor, id),
      else: simulation_retry(actor, id)
  end

  defp simulation_retry(actor, id) do
    Tenant.transaction(actor, fn actor ->
      message = Repo.get_by(Message, id: id, organization_id: actor.organization_id)
      unless message, do: Repo.rollback(:not_found)

      ticket =
        Repo.one!(
          from t in Ticket,
            where: t.id == ^message.ticket_id and t.organization_id == ^actor.organization_id,
            lock: "FOR UPDATE"
        )

      version = Repo.get!(Instantflow.WorkflowCatalog.Version, ticket.workflow_version_id)
      events = Instantflow.WorkflowRuntime.History.authorized_query(actor, ticket, version)
      deliveries = Instantflow.WorkflowRuntime.History.deliveries_query(events, ticket)

      unless Instantflow.WorkflowRuntime.Policy.discover?(actor, ticket, version) and
               Instantflow.WorkflowRuntime.Policy.retry?(actor, ticket, version) and
               Repo.exists?(from m in deliveries, where: m.id == ^id),
             do: Repo.rollback(:forbidden)

      Instantflow.WorkflowCatalog.Retirement.require_active!(ticket.workflow_version_id)

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
