defmodule InstantflowWeb.RefreshNotificationsTest do
  use ExUnit.Case, async: true
  alias InstantflowWeb.RefreshNotifications

  test "record drains are scoped and preserve commands, permission checks and unrelated reasons" do
    socket = %{
      view: InstantflowWeb.RequestLive,
      assigns: %{current_scope: %{organization_id: 1}, data: %{ticket: %{id: 2}}}
    }

    preserved = [
      {:ticket_changed, 2, 2},
      {:ticket_changed, 1, 3},
      :access_revoked,
      :revalidate_organization,
      :workspaces_changed,
      {:"$gen_call", self(), :browser_event}
    ]

    for message <- [:reconcile, {:ticket_changed, 1, 2}, :permissions_changed] ++ preserved,
        do: send(self(), message)

    RefreshNotifications.coalesce(socket, {:ticket_changed, 1, 2})
    for message <- preserved, do: assert_receive(^message)
    refute_receive :reconcile, 0
    refute_receive :permissions_changed, 0
    refute_receive {:ticket_changed, 1, 2}, 0
  end

  test "each drain has a hard bound and does not consume a presence update as a full refresh" do
    socket = %{view: InstantflowWeb.ProcessLive}
    for _ <- 1..101, do: send(self(), :operations_changed)
    send(self(), :revalidate_organization)
    RefreshNotifications.coalesce(socket, :reconcile)
    assert_receive :operations_changed
    refute_receive :operations_changed, 0
    assert_receive :revalidate_organization

    socket = %{
      view: InstantflowWeb.RequestLive,
      assigns: %{current_scope: %{organization_id: 1}, data: %{ticket: %{id: 2}}}
    }

    presence = %Phoenix.Socket.Broadcast{
      topic: Instantflow.Collaboration.Presence.topic(1, 2),
      event: "presence_diff"
    }

    send(self(), presence)
    RefreshNotifications.coalesce(socket, :permissions_changed)
    assert_receive ^presence
    send(self(), :permissions_changed)
    send(self(), presence)
    RefreshNotifications.coalesce(socket, presence)
    assert_receive :permissions_changed
    refute_receive ^presence, 0
  end
end
