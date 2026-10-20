defmodule Instantflow.Delivery do
  @moduledoc "Durable demo-only delivery. Refresh is at least once; deterministic simulation results are stored transactionally."
  import Ecto.Query
  alias Instantflow.{Identity, Repo, WorkflowRuntime}
  alias Instantflow.Delivery.{Attempt, Message}
  alias Instantflow.WorkflowRuntime.Ticket

  def pending_ids,
    do:
      Repo.all(
        from m in Message, where: m.status == "pending", order_by: m.id, limit: 100, select: m.id
      )

  def process(id) do
    case Repo.get(Message, id) do
      %Message{kind: "refresh", status: "pending"} = message ->
        # Publish before acknowledging: a crash leaves this pending for replay. Duplicates are safe invalidations.
        Phoenix.PubSub.broadcast(
          Instantflow.PubSub,
          topic(message.ticket_id),
          {:ticket_changed, message.ticket_id}
        )

        complete(id)

      %Message{status: "pending"} ->
        complete(id)

      _ ->
        {:ok, :already_processed}
    end
  end

  def drain, do: Enum.map(pending_ids(), &process/1)

  def retry(actor, id) do
    Repo.transaction(fn ->
      actor = Identity.lock_scope!(actor)
      message = Repo.get(Message, id)
      unless message, do: Repo.rollback(:not_found)
      ticket = Repo.one!(from t in Ticket, where: t.id == ^message.ticket_id, lock: "FOR UPDATE")

      unless actor.department_id == ticket.assigned_department_id and
               match?({:ok, _}, WorkflowRuntime.get(actor, ticket.id)),
             do: Repo.rollback(:forbidden)

      message = Repo.one!(from m in Message, where: m.id == ^id, lock: "FOR UPDATE")
      unless message.status == "failed", do: Repo.rollback(:not_failed)

      message
      |> Ecto.Changeset.change(status: "pending", retried_by_id: actor.user_id)
      |> Repo.update!()
    end)
  end

  def topic(id), do: "ticket:#{id}"

  defp complete(id) do
    Repo.transaction(fn ->
      message = Repo.one!(from m in Message, where: m.id == ^id, lock: "FOR UPDATE")

      if message.status == "pending" do
        number = message.attempts + 1

        result =
          if message.behavior == "failure" or (message.behavior == "fail_once" and number == 1),
            do: "failed",
            else: "succeeded"

        Repo.insert!(%Attempt{
          outbox_message_id: id,
          number: number,
          result: result,
          actor_id: message.retried_by_id
        })

        if message.kind != "refresh" do
          Repo.insert!(%Message{
            ticket_id: message.ticket_id,
            event_id: message.event_id,
            key: "delivery-result:#{message.id}:#{number}",
            kind: "refresh"
          })
        end

        message |> Ecto.Changeset.change(status: result, attempts: number) |> Repo.update!()
      else
        :already_processed
      end
    end)
  end
end
