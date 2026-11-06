defmodule Instantflow.Collaboration.Presence do
  @moduledoc "Advisory editing presence. No values, locks, or client-supplied identities."
  use Phoenix.Presence, otp_app: :instantflow, pubsub_server: Instantflow.PubSub
  import Ecto.Query
  alias Instantflow.{Access, Repo, Tenant}
  alias Instantflow.Identity.{Membership, User}
  alias Instantflow.WorkflowCatalog.{Retirement, Version}
  alias Instantflow.WorkflowRuntime.{AccessFacts, Policy, Ticket}
  @peer_batch_size 250

  def heartbeat(scope, ticket_id, section) do
    case project(scope, ticket_id, section) do
      {:ok, projection} ->
        {:ok, projection}

      error ->
        untrack(self(), topic(scope.organization_id, ticket_id), to_string(scope.id))
        error
    end
  end

  def editors(scope, data) do
    case project(scope, data.ticket.id) do
      {:ok, projection} -> projection.editors
      _ -> []
    end
  end

  @doc false
  def editors_in_context(context, id) do
    scope = Tenant.context_scope!(context)
    {ticket, version} = Instantflow.WorkflowRuntime.RecordRead.fetch!(context, id)
    facts = Map.fetch!(AccessFacts.load([scope], ticket, version), scope.id)

    keys =
      version.definition["sections"]
      |> Enum.filter(&Policy.section?(scope, ticket, version, &1, :read, facts))
      |> Enum.map(& &1["key"])

    if keys == [] or Retirement.retired?(version.id),
      do: [],
      else: authorized_editors(scope, ticket, version, keys)
  end

  @doc "Current presence and access shape, without section values, history, files or control directories."
  def project(scope, ticket_id, active_section \\ nil) do
    Tenant.read(
      scope,
      fn fresh ->
        ticket = Repo.get(Ticket, ticket_id) || Repo.rollback(:not_found)
        version = Repo.get!(Version, ticket.workflow_version_id)
        facts = Map.fetch!(AccessFacts.load([fresh], ticket, version), fresh.id)
        sections = version.definition["sections"]

        readable =
          Enum.filter(sections, &Policy.section?(fresh, ticket, version, &1, :read, facts))

        if readable == [], do: Repo.rollback(:forbidden)
        archived? = Retirement.retired?(version.id)

        editable =
          readable
          |> Enum.filter(
            &(not archived? and Policy.section?(fresh, ticket, version, &1, :edit, facts))
          )
          |> Enum.map(& &1["key"])

        if active_section do
          unless active_section in editable, do: Repo.rollback(:forbidden)
          touch(fresh, ticket.id, active_section)
        end

        keys = Enum.map(readable, & &1["key"])

        {:ok,
         %{
           authorization: Access.fingerprint(fresh),
           revision: ticket.revision,
           version_id: version.id,
           archived?: archived?,
           readable: keys,
           editable: editable,
           editors: if(archived?, do: [], else: authorized_editors(fresh, ticket, version, keys))
         }}
      end,
      {:error, :forbidden}
    )
  end

  defp touch(scope, ticket_id, section) do
    topic = topic(scope.organization_id, ticket_id)
    meta = %{membership_id: scope.id, section: section, seen_at: System.system_time(:second)}

    case update(self(), topic, to_string(scope.id), meta) do
      {:error, :nopresence} -> track(self(), topic, to_string(scope.id), meta)
      result -> result
    end
  end

  defp authorized_editors(scope, ticket, version, visible) do
    cutoff = System.system_time(:second) - 45

    metas =
      topic(scope.organization_id, ticket.id)
      |> list()
      |> Enum.flat_map(fn {_key, %{metas: metas}} -> metas end)
      |> Enum.filter(fn
        %{membership_id: id, section: section, seen_at: seen_at}
        when is_integer(id) and id > 0 and id < 9_223_372_036_854_775_807 and is_integer(seen_at) ->
          section in visible and seen_at > cutoff

        _ ->
          false
      end)
      |> Enum.uniq_by(&{&1.membership_id, &1.section})
      |> Enum.group_by(& &1.membership_id)

    # Peer facts are read under the viewer's shared authorization gate. No peer
    # record projection or peer lock upgrade is needed for this advisory snapshot.
    metas
    |> Map.keys()
    |> Enum.sort()
    |> Enum.chunk_every(@peer_batch_size)
    |> Enum.flat_map(fn ids ->
      members =
        Repo.all(
          from m in Membership,
            join: u in User,
            on: u.id == m.user_id,
            where:
              m.organization_id == ^scope.organization_id and m.id in ^ids and m.active and
                u.active,
            order_by: m.id,
            select: {m, u.name}
        )
        |> Enum.map(fn {member, name} ->
          %{member | user: %User{id: member.user_id, name: name}}
        end)

      grants =
        members
        |> Enum.reject(&(&1.id == scope.id))
        |> Access.load_many()
        |> Map.new(&{&1.id, &1.grants})

      members =
        Enum.map(members, fn member ->
          %{
            member
            | grants:
                if(member.id == scope.id, do: scope.grants, else: Map.get(grants, member.id, []))
          }
        end)

      facts = AccessFacts.load(members, ticket, version)

      Enum.flat_map(members, fn member ->
        Enum.flat_map(Map.fetch!(metas, member.id), fn meta ->
          section = Enum.find(version.definition["sections"], &(&1["key"] == meta.section))

          if Policy.section?(member, ticket, version, section, :read, facts[member.id]) and
               Policy.section?(member, ticket, version, section, :edit, facts[member.id]),
             do: [%{section: meta.section, name: member.user.name, user_id: member.user_id}],
             else: []
        end)
      end)
    end)
    |> Enum.uniq_by(&{&1.section, &1.user_id})
  end

  def topic(organization_id, ticket_id),
    do: "organization:#{organization_id}:ticket:#{ticket_id}:presence"
end
