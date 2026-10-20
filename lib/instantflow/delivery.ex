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
      message =
        Repo.one(
          from m in Message,
            where: m.id == ^id and m.organization_id == ^organization_id,
            lock: "FOR UPDATE"
        )

      if message && message.status == "pending" do
        if message.kind == "refresh",
          do:
            Phoenix.PubSub.broadcast(
              Instantflow.PubSub,
              topic(organization_id, message.ticket_id),
              {:ticket_changed, organization_id, message.ticket_id}
            )

        number = message.attempts + 1

        result =
          if message.behavior == "failure" or (message.behavior == "fail_once" and number == 1),
            do: "failed",
            else: "succeeded"

        Repo.insert!(%Attempt{
          organization_id: organization_id,
          outbox_message_id: id,
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
    end)
  end

  def drain do
    %{rows: rows} = Repo.query!("SELECT id FROM dispatch_organizations()")

    # Each organization receives one bounded batch each pass, irrespective of the preceding tenant's backlog.
    Enum.map(rows, fn [id] -> {id, Enum.map(pending_ids(id), &process(id, &1))} end)
  end

  def retry(actor, id) do
    Tenant.transaction(actor, fn actor ->
      message = Repo.get_by(Message, id: id, organization_id: actor.organization_id)
      unless message, do: Repo.rollback(:not_found)

      ticket =
        Repo.one!(
          from t in Ticket,
            where: t.id == ^message.ticket_id and t.organization_id == ^actor.organization_id,
            lock: "FOR UPDATE"
        )

      unless actor.department_id == ticket.assigned_department_id and
               match?({:ok, _}, WorkflowRuntime.get(actor, ticket.id)),
             do: Repo.rollback(:forbidden)

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
