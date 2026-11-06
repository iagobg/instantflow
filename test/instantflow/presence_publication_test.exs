defmodule Instantflow.PresencePublicationTest do
  use Instantflow.DataCase, async: true
  import Instantflow.CollaborationFixtures
  import Instantflow.WorkflowFixtures
  alias Instantflow.{Access, Repo}
  alias Instantflow.Collaboration.Presence
  alias Instantflow.Diagnostics.QueryProbe

  test "recent same-section events retain presence while checking current authority" do
    f = collaborative_fixture()
    id = create_ticket(f)
    topic = Presence.topic(f.requester.organization_id, id)
    Phoenix.PubSub.subscribe(Instantflow.PubSub, topic)

    assert {:ok, _} = Presence.heartbeat(f.requester, id, "notes")
    [initial] = metas(topic, f.requester)
    await_ref(topic, :joins, initial.phx_ref)

    {{:ok, projection}, report} =
      QueryProbe.capture(fn -> Presence.heartbeat(f.requester, id, "notes") end)

    assert "notes" in projection.editable
    assert report.groups.authorization.statements > 0
    assert report.groups.history.statements == 0
    assert report.groups.documents.statements == 0
    assert metas(topic, f.requester) == [initial]
    refute_receive %Phoenix.Socket.Broadcast{topic: ^topic, event: "presence_diff"}
  end

  test "section changes, elapsed intervals and backwards clock jumps publish immediately" do
    f = collaborative_fixture()
    id = create_ticket(f)
    topic = Presence.topic(f.requester.organization_id, id)
    assert {:ok, _} = Presence.heartbeat(f.requester, id, "request")
    [first] = metas(topic, f.requester)

    assert {:ok, _} = Presence.heartbeat(f.requester, id, "notes")
    [changed] = metas(topic, f.requester)
    assert changed.section == "notes"
    assert changed.phx_ref != first.phx_ref

    for offset <- [-15, -46, 60] do
      {:ok, previous} =
        Presence.update(self(), topic, to_string(f.requester.id), %{
          membership_id: f.requester.id,
          section: "notes",
          seen_at: System.system_time(:second) + offset
        })

      before = System.system_time(:second)

      assert {:ok, %{editors: [%{section: "notes"}]}} =
               Presence.heartbeat(f.requester, id, "notes")

      [renewed] = metas(topic, f.requester)
      assert renewed.phx_ref != previous
      assert renewed.seen_at >= before
      assert renewed.seen_at <= System.system_time(:second)
    end
  end

  test "missing presence is recreated within the publication interval" do
    f = collaborative_fixture()
    id = create_ticket(f)
    topic = Presence.topic(f.requester.organization_id, id)
    assert {:ok, _} = Presence.heartbeat(f.requester, id, "notes")
    [first] = metas(topic, f.requester)
    :ok = Presence.untrack(self(), topic, to_string(f.requester.id))
    assert Presence.get_by_key(topic, to_string(f.requester.id)) == []
    assert {:ok, _} = Presence.heartbeat(f.requester, id, "notes")
    [renewed] = metas(topic, f.requester)
    assert renewed.phx_ref != first.phx_ref
  end

  test "tabs of the same membership keep separate publication intervals and departure cleanup" do
    f = collaborative_fixture()
    id = create_ticket(f)
    topic = Presence.topic(f.requester.organization_id, id)
    Phoenix.PubSub.subscribe(Instantflow.PubSub, topic)
    assert {:ok, _} = Presence.heartbeat(f.requester, id, "notes")
    [first] = metas(topic, f.requester)
    await_ref(topic, :joins, first.phx_ref)

    tab = start_supervised!({Agent, fn -> :ok end})
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), tab)

    assert {:ok, _} =
             Agent.get(tab, fn _ -> Presence.heartbeat(f.requester, id, "notes") end)

    assert [second] = Enum.reject(metas(topic, f.requester), &(&1.phx_ref == first.phx_ref))
    await_ref(topic, :joins, second.phx_ref)
    assert {:ok, _} = Presence.heartbeat(f.requester, id, "request")
    assert second in metas(topic, f.requester)

    assert {:ok, _} =
             Agent.get(tab, fn _ -> Presence.heartbeat(f.requester, id, "notes") end)

    assert second in metas(topic, f.requester)
    ref = Process.monitor(tab)
    stop_supervised!(Agent)
    assert_receive {:DOWN, ^ref, :process, ^tab, :shutdown}
    await_ref(topic, :leaves, second.phx_ref)
    assert [%{section: "request"}] = metas(topic, f.requester)
  end

  test "revocation withdraws a recently published presence without waiting for the interval" do
    f = collaborative_fixture()
    id = create_ticket(f)
    topic = Presence.topic(f.reviewer.organization_id, id)

    assert {:ok, {_, grant}} =
             Access.grant(f.admin, f.reviewer.id, f.reviewer.department_id, "finance")

    assert {:ok, _} = Presence.heartbeat(f.reviewer, id, "finance")
    assert [%{section: "finance"}] = metas(topic, f.reviewer)
    assert {:ok, _} = Access.revoke(f.admin, grant.id)
    assert {:error, :forbidden} = Presence.heartbeat(f.reviewer, id, "finance")
    assert Presence.get_by_key(topic, to_string(f.reviewer.id)) == []
  end

  defp metas(topic, member), do: Presence.get_by_key(topic, to_string(member.id)).metas

  defp await_ref(topic, kind, ref) do
    assert_receive %Phoenix.Socket.Broadcast{
                     topic: ^topic,
                     event: "presence_diff",
                     payload: diff
                   },
                   1_000

    if not Enum.any?(diff[kind], fn {_, %{metas: metas}} ->
         Enum.any?(metas, &(&1.phx_ref == ref))
       end),
       do: await_ref(topic, kind, ref)

    Presence.list(topic)
  end
end
