defmodule Instantflow.WorkflowRuntime.Notifications do
  @moduledoc """
  Current list recipients for one tenant-bound dispatcher batch.

  Called inside the outbox's authorization transaction with its bounded ticket
  IDs. Memberships and grants are read in pages of 250, once per batch, while
  each record retains its pinned policy and current supporting facts. A generic
  invalidation is sufficient when any record is discoverable; no record IDs or
  values are published and each receiving view reauthorizes its own projection.
  """
  import Ecto.Query
  alias Instantflow.{Access, Repo, WorkflowRuntime}
  alias Instantflow.Identity.{Membership, User}
  alias Instantflow.WorkflowCatalog.{Capabilities, Version}
  alias Instantflow.WorkflowRuntime.{AccessFacts, Policy, Ticket}

  def invalidate_lists(organization_id, ticket_id) when is_integer(ticket_id),
    do: invalidate_lists(organization_id, [ticket_id])

  def invalidate_lists(_organization_id, []), do: :ok

  def invalidate_lists(organization_id, ticket_ids) when is_list(ticket_ids) do
    tickets =
      Repo.all(
        from t in Ticket,
          where: t.organization_id == ^organization_id and t.id in ^ticket_ids,
          order_by: t.id
      )

    version_ids = tickets |> Enum.map(& &1.workflow_version_id) |> Enum.uniq()
    versions = Repo.all(from v in Version, where: v.id in ^version_ids) |> Map.new(&{&1.id, &1})
    records = Enum.map(tickets, &{&1, Map.fetch!(versions, &1.workflow_version_id)})

    # Accounts can be shared by several workflows. Keep the organization-wide
    # signal for finance-capable pinned records, once for the whole batch.
    if Enum.any?(records, fn {_, version} ->
         Capabilities.enabled?(version.definition, "finance")
       end),
       do: Instantflow.Finance.broadcast(organization_id)

    if records != [], do: invalidate_member_batch(organization_id, records, 0)
  end

  defp invalidate_member_batch(organization_id, records, after_id) do
    members =
      Repo.all(
        from m in Membership,
          join: u in User,
          on: u.id == m.user_id,
          where:
            m.organization_id == ^organization_id and m.active and u.active and m.id > ^after_id,
          order_by: m.id,
          limit: 250
      )
      |> Access.load_many()

    recipients =
      Enum.reduce(records, MapSet.new(), fn {ticket, version}, recipients ->
        remaining = Enum.reject(members, &MapSet.member?(recipients, &1.id))
        facts = AccessFacts.load(remaining, ticket, version)

        Enum.reduce(remaining, recipients, fn member, recipients ->
          if Policy.discover?(member, ticket, version, Map.fetch!(facts, member.id)),
            do: MapSet.put(recipients, member.id),
            else: recipients
        end)
      end)

    for member <- members,
        MapSet.member?(recipients, member.id),
        do:
          Phoenix.PubSub.broadcast(
            Instantflow.PubSub,
            WorkflowRuntime.list_topic(member),
            :requests_changed
          )

    if length(members) == 250,
      do: invalidate_member_batch(organization_id, records, List.last(members).id)
  end
end
