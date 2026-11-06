defmodule Instantflow.PresenceEfficiencyTest do
  use Instantflow.DataCase, async: false
  import Instantflow.CollaborationFixtures
  import Instantflow.WorkflowFixtures

  alias Instantflow.{
    Access,
    BuilderFixtures,
    DocumentHistoryFixtures,
    Participants,
    WorkflowRuntime
  }

  alias Instantflow.Collaboration.Presence
  alias Instantflow.Diagnostics.QueryProbe
  alias Instantflow.Identity.{Membership, User}

  test "peer checks use a fixed batch cost and exclude inactive or expired peers" do
    f = collaborative_fixture()
    id = create_ticket(f)
    peers = for n <- 1..103, do: peer(f, n)
    {first, rest} = Enum.split(peers, 3)
    Enum.each(first, &track(&1, id, "notes"))
    {{:ok, a}, small} = measure("presence_3_peers", fn -> Presence.project(f.requester, id) end)
    assert length(a.editors) == 3
    Enum.each(rest, &track(&1, id, "notes"))
    {{:ok, b}, large} = measure("presence_103_peers", fn -> Presence.project(f.requester, id) end)
    assert length(b.editors) == 103
    assert small.statements == large.statements
    assert small.groups.history.statements == 0
    assert large.groups.documents.statements == 0
    assert large.content_bytes == 0

    [inactive_user, inactive_member, expired | _] = peers
    Repo.update_all(from(u in User, where: u.id == ^inactive_user.user_id), set: [active: false])

    Repo.update_all(from(m in Membership, where: m.id == ^inactive_member.id),
      set: [active: false]
    )

    Presence.update(self(), Presence.topic(1, id), to_string(expired.id), %{
      membership_id: expired.id,
      section: "notes",
      seen_at: System.system_time(:second) - 46
    })

    assert {:ok, current} = Presence.project(f.requester, id)
    assert length(current.editors) == 100

    refute Enum.any?(
             current.editors,
             &(&1.user_id in [inactive_user.user_id, inactive_member.user_id, expired.user_id])
           )
  end

  test "named assignment facts require current role and department eligibility" do
    f = Instantflow.IncidentFixtures.incident_fixture()
    id = Instantflow.IncidentFixtures.report(f)
    Instantflow.IncidentFixtures.followup(f, id)
    assert {:ok, p} = Presence.heartbeat(f.counselor, id, "support")
    assert_parity(f.counselor, id, p)
    assert [%{section: "support"}] = p.editors
    assert {:ok, dean} = Presence.project(f.dean, id)
    assert dean.editors == []
    grant = Enum.find(f.counselor.grants, &(&1.role == "counselor"))
    assert {:ok, _} = Access.revoke(f.admin, grant.id)
    assert {:error, :forbidden} = Presence.project(f.counselor, id)
  end

  test "participant verification and retirement remain authoritative without document reads" do
    f = DocumentHistoryFixtures.fixture(1)

    {{:ok, p}, report} =
      measure("presence_participant", fn ->
        Presence.heartbeat(f.visitor, f.ticket_id, "customer_details")
      end)

    assert_parity(f.visitor, f.ticket_id, p)
    assert report.groups.documents.statements == 0
    assert report.groups.history.statements == 0

    assert {:ok, _} =
             Participants.command(
               f.admin,
               BuilderFixtures.participant_command(f.ticket_id, f.visitor.id, "revoke", 2)
             )

    assert {:error, :forbidden} = Presence.project(f.visitor, f.ticket_id)

    Repo.insert_all("retired_workflow_versions", [
      %{
        organization_id: 1,
        version_id: f.version.id,
        reason: "Synthetic archive",
        inserted_at: DateTime.utc_now(:second)
      }
    ])

    assert {:ok, %{editable: [], editors: [], archived?: true}} =
             Presence.project(f.clerk, f.ticket_id)

    assert {:error, :forbidden} = Presence.heartbeat(f.clerk, f.ticket_id, "request")
  end

  defp assert_parity(actor, id, p) do
    assert {:ok, full} = WorkflowRuntime.get(actor, id)
    assert MapSet.new(p.readable) == MapSet.new(full.sections, & &1.key)
    assert p.editable == full.editable
    assert p.authorization == full.authorization
  end

  defp peer(f, n) do
    user =
      Repo.insert!(%User{
        email: "presence-#{n}@synthetic.invalid",
        name: "Synthetic #{n}",
        password_hash: f.reviewer.user.password_hash
      })

    Repo.insert!(%Membership{
      organization_id: 1,
      user_id: user.id,
      department_id: f.reviewer.department_id,
      role: f.reviewer.role
    })
  end

  defp track(member, id, section) do
    assert {:ok, _} =
             Presence.track(self(), Presence.topic(1, id), to_string(member.id), %{
               membership_id: member.id,
               section: section,
               seen_at: System.system_time(:second)
             })
  end

  defp measure(scenario, fun) do
    {result, report} = QueryProbe.capture(fun)

    if path = System.get_env("DB_EFFICIENCY_REPORT"),
      do:
        File.write!(path, Jason.encode!(Map.put(report, :scenario, scenario)) <> "\n", [:append])

    {result, report}
  end
end
