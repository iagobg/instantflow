defmodule Instantflow.Collaboration.Presence do
  @moduledoc "Advisory editing presence. No values, locks, or client-supplied identities."
  use Phoenix.Presence, otp_app: :instantflow, pubsub_server: Instantflow.PubSub
  alias Instantflow.{Identity, WorkflowRuntime}

  def heartbeat(scope, ticket_id, section) do
    topic = topic(scope.organization_id, ticket_id)

    with {:ok, data} <- WorkflowRuntime.get(scope, ticket_id),
         true <- section in data.editable do
      meta = %{membership_id: scope.id, section: section, seen_at: System.system_time(:second)}

      case update(self(), topic, to_string(scope.id), meta) do
        {:error, :nopresence} -> track(self(), topic, to_string(scope.id), meta)
        result -> result
      end
    else
      _ -> untrack(self(), topic, to_string(scope.id))
    end
  end

  def editors(scope, data) do
    # Cached section keys are not evidence of the viewer's current permission.
    case WorkflowRuntime.get(scope, data.ticket.id) do
      {:ok, fresh} -> authorized_editors(scope, fresh)
      _ -> []
    end
  end

  defp authorized_editors(scope, data) do
    visible = Enum.map(data.sections, & &1.key)

    topic(scope.organization_id, data.ticket.id)
    |> list()
    |> Enum.flat_map(fn {_key, %{metas: metas}} ->
      Enum.flat_map(metas, fn meta ->
        if meta.section in visible and meta.seen_at > System.system_time(:second) - 45 do
          # Resolve current local membership and section rights before exposing any name.
          case Instantflow.Tenant.read(scope, fn _ ->
                 Instantflow.Repo.get(Instantflow.Identity.Membership, meta.membership_id)
               end) do
            nil ->
              []

            member ->
              peer = Identity.scope(member.user_id, scope.organization_id)

              case peer && WorkflowRuntime.get(peer, data.ticket.id) do
                {:ok, peer_data} ->
                  if meta.section in peer_data.editable,
                    do: [%{section: meta.section, name: peer.user.name, user_id: peer.user_id}],
                    else: []

                _ ->
                  []
              end
          end
        else
          []
        end
      end)
    end)
    |> Enum.uniq_by(&{&1.section, &1.user_id})
  end

  def topic(organization_id, ticket_id),
    do: "organization:#{organization_id}:ticket:#{ticket_id}:presence"
end
