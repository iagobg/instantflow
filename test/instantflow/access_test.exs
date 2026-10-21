defmodule Instantflow.AccessTest do
  use Instantflow.DataCase, async: true
  import Instantflow.CollaborationFixtures
  import Instantflow.WorkflowFixtures
  import Instantflow.IdentityFixtures
  alias Instantflow.{Access, Identity, Tenant, WorkflowRuntime}
  alias Instantflow.Identity.{Department, Membership}

  test "grants pair roles with departments, project restricted sections, and revoke immediately" do
    f = collaborative_fixture()
    id = create_ticket(f)
    other = Repo.insert!(%Department{organization_id: f.admin.organization_id, name: "Outro"})
    {:ok, {_, wrong_grant}} = Access.grant(f.admin, f.reviewer.id, other.id, "finance")
    {:ok, data} = WorkflowRuntime.get(f.reviewer, id)
    refute Enum.any?(data.sections, &(&1.key == "finance"))
    refute Enum.any?(data.version.definition["sections"], &(&1["key"] == "finance"))

    assert {:ok, {_, grant}} =
             Access.grant(f.admin, f.reviewer.id, f.reviewer.department_id, "finance")

    {:ok, data} = WorkflowRuntime.get(f.reviewer, id)
    assert Enum.any?(data.sections, &(&1.key == "finance"))
    command = section_command(data, "finance", %{"summary" => "Reservado"})
    assert {:ok, _} = WorkflowRuntime.command(f.reviewer, command)
    {:ok, outsider_data} = WorkflowRuntime.get(f.requester, id)
    refute Enum.any?(outsider_data.events, &(&1.operation == "save:finance"))
    assert {:ok, _} = Access.revoke(f.admin, grant.id)
    assert {:error, :forbidden} = WorkflowRuntime.command(f.reviewer, %{command | "key" => key()})
    {:ok, data} = WorkflowRuntime.get(f.reviewer, id)
    refute Enum.any?(data.sections, &(&1.key == "finance"))
    assert {:ok, _} = Access.revoke(f.admin, wrong_grant.id)
  end

  test "administration alone cannot discover records or inflate counts" do
    f = collaborative_fixture()
    id = create_ticket(f)
    result = WorkflowRuntime.search(f.requester, %{"query" => to_string(id)})
    assert result.total == 1
    assert result.filtered == 1
    assert result.counts == %{"draft" => 1}

    department =
      Repo.insert!(%Department{organization_id: f.admin.organization_id, name: "Administração"})

    Repo.get!(Membership, f.admin.id)
    |> Ecto.Changeset.change(department_id: department.id)
    |> Repo.update!()

    assert WorkflowRuntime.search(f.admin).total == 0
    assert {:error, :not_found} = WorkflowRuntime.get(f.admin, id)
    assert Identity.admin?(f.admin)
    Phoenix.PubSub.subscribe(Instantflow.PubSub, WorkflowRuntime.list_topic(f.admin))

    {:ok, _} =
      Tenant.raw(f.admin.organization_id, fn ->
        WorkflowRuntime.invalidate_lists(f.admin.organization_id, id)
      end)

    refute_receive :requests_changed
    Phoenix.PubSub.subscribe(Instantflow.PubSub, WorkflowRuntime.list_topic(f.requester))

    {:ok, _} =
      Tenant.raw(f.admin.organization_id, fn ->
        WorkflowRuntime.invalidate_lists(f.admin.organization_id, id)
      end)

    assert_receive :requests_changed
  end

  test "finance-sensitive self approval is denied even with overlapping local roles" do
    f = collaborative_fixture()
    id = create_ticket(f)
    {:ok, _} = Access.grant(f.admin, f.requester.id, f.requester.department_id, "finance")
    {:ok, _} = save(f.requester, id, values())
    {:ok, _} = transition(f.requester, id, "submit")
    assert {:error, :forbidden} = transition(f.requester, id, "approve")
    assert {:ok, _} = transition(f.reviewer, id, "approve")
  end

  test "grants cannot cross tenant foreign keys and additional departments can discover records" do
    f = collaborative_fixture()
    id = create_ticket(f)
    other = Repo.insert!(%Department{organization_id: f.admin.organization_id, name: "Outro"})
    member = staff_fixture("staff")

    Repo.get!(Membership, member.id)
    |> Ecto.Changeset.change(department_id: other.id)
    |> Repo.update!()

    assert WorkflowRuntime.list(member) == []
    {:ok, _} = Access.grant(f.admin, member.id, f.reviewer.department_id, "finance")
    assert WorkflowRuntime.search(member).total == 1
    {:ok, data} = WorkflowRuntime.get(member, id)
    assert Enum.map(data.sections, & &1.key) == ["finance"]
    assert {:ok, [grant]} = Tenant.transaction(member, fn a -> a.grants end)
    assert grant.organization_id == member.organization_id
  end

  test "presence exposes only authorized sections and expires without granting authority" do
    f = collaborative_fixture()
    id = create_ticket(f)
    {:ok, {_, grant}} = Access.grant(f.admin, f.reviewer.id, f.reviewer.department_id, "finance")
    alias Instantflow.Collaboration.Presence
    assert {:ok, _} = Presence.heartbeat(f.reviewer, id, "finance")
    {:ok, public} = WorkflowRuntime.get(f.requester, id)
    assert Presence.editors(f.requester, public) == []
    {:ok, restricted} = WorkflowRuntime.get(f.reviewer, id)
    assert [%{section: "finance"}] = Presence.editors(f.reviewer, restricted)

    {:ok, {_, viewer_grant}} =
      Access.grant(f.admin, f.requester.id, f.requester.department_id, "finance")

    {:ok, cached_viewer} = WorkflowRuntime.get(f.requester, id)
    assert [%{section: "finance"}] = Presence.editors(f.requester, cached_viewer)
    {:ok, _} = Access.revoke(f.admin, viewer_grant.id)
    assert Presence.editors(f.requester, cached_viewer) == []
    {:ok, _} = Access.revoke(f.admin, grant.id)
    assert Presence.editors(f.reviewer, restricted) == []
    assert {:ok, _} = Presence.heartbeat(f.reviewer, id, "notes")
    topic = Presence.topic(f.reviewer.organization_id, id)

    {:ok, _} =
      Presence.update(self(), topic, to_string(f.reviewer.id), %{
        membership_id: f.reviewer.id,
        section: "notes",
        seen_at: System.system_time(:second) - 46
      })

    assert Presence.editors(f.requester, public) == []
  end

  test "actor-only history excludes its reason and deliveries from the requester projection" do
    f = collaborative_fixture()

    definition =
      Map.update!(f.definition, "transitions", fn edges ->
        Enum.map(edges, fn edge ->
          if edge["key"] == "approve",
            do:
              edge
              |> Map.put("history_visibility", "actors")
              |> Map.put("require_reason", true)
              |> Map.put("actions", [
                %{"type" => "simulate_provisioning", "behavior" => "success"}
              ]),
            else: edge
        end)
      end)

    {:ok, version} = Instantflow.WorkflowCatalog.publish(f.admin, definition, f.bindings, 2)
    id = create_ticket(%{f | version: version})
    {:ok, _} = save(f.requester, id, values())
    {:ok, _} = transition(f.requester, id, "submit")
    {:ok, _} = transition(f.reviewer, id, "approve", "Parecer reservado")
    {:ok, requester} = WorkflowRuntime.get(f.requester, id)
    {:ok, reviewer} = WorkflowRuntime.get(f.reviewer, id)
    refute Enum.any?(requester.events, &(&1.operation == "approve"))
    refute Enum.any?(requester.deliveries, &(&1.kind == "simulate_provisioning"))
    refute Enum.any?(requester.version.definition["transitions"], &(&1["key"] == "approve"))
    assert Enum.any?(reviewer.events, &(&1.reason == "Parecer reservado"))
    assert Enum.any?(reviewer.deliveries, &(&1.kind == "simulate_provisioning"))
  end
end
