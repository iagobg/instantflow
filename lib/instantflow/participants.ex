defmodule Instantflow.Participants do
  @moduledoc """
  Record-bound verified relationships, independent of invitations and login.

  Managers are declared in the record's pinned definition. Mutations acquire
  the exclusive tenant authorization gate before business locks; runtime reads
  and writes acquire its shared counterpart. A committed revocation therefore
  fences subsequent protected commands and receipt replay.
  """
  import Ecto.Query
  alias Instantflow.{Repo, Tenant, WorkflowRuntime}
  alias Instantflow.Identity.Membership
  alias Instantflow.Participants.Relationship
  alias Instantflow.WorkflowCatalog.Version
  alias Instantflow.WorkflowRuntime.{Policy, Receipt, Ticket}

  def command(actor, command) when is_map(command) do
    if valid_command?(command) do
      result =
        Tenant.authorize_change(actor, fn scope ->
          ticket =
            Repo.one(
              from t in Ticket,
                where:
                  t.id == ^command["ticket_id"] and t.organization_id == ^scope.organization_id,
                lock: "FOR UPDATE"
            ) || Repo.rollback(:not_found)

          version = Repo.get!(Version, ticket.workflow_version_id)

          unless manage?(scope, ticket, version, command["relationship"]),
            do: Repo.rollback(:forbidden)

          Instantflow.WorkflowCatalog.Retirement.require_active!(version.id)

          member =
            Repo.get_by(Membership,
              id: command["membership_id"],
              organization_id: scope.organization_id,
              active: true
            ) || Repo.rollback(:not_found)

          if command["operation"] in ~w(create verify) do
            unless Repo.exists?(
                     from [m, _u] in candidate_query(scope, version, command["relationship"]),
                       where: m.id == ^command["membership_id"]
                   ),
                   do: Repo.rollback(:ineligible_participant)
          end

          operation = "participants:" <> command["operation"]
          digest = :crypto.hash(:sha256, :erlang.term_to_binary(command, [:deterministic]))

          receipt =
            Repo.get_by(Receipt,
              organization_id: scope.organization_id,
              actor_id: scope.user_id,
              operation: operation,
              key: command["key"]
            )

          if receipt do
            unless receipt.digest == digest, do: Repo.rollback(:idempotency_mismatch)
            receipt.result
          else
            relationship = apply!(scope, ticket, member, command)

            updated =
              ticket |> Ecto.Changeset.change(revision: ticket.revision + 1) |> Repo.update!()

            WorkflowRuntime.record(
              updated,
              scope,
              "participant:" <> command["operation"] <> ":" <> relationship.relationship,
              ticket.stage,
              nil,
              []
            )

            value = %{
              "relationship_id" => relationship.id,
              "revision" => relationship.revision,
              "status" => relationship.status
            }

            Repo.insert!(%Receipt{
              organization_id: scope.organization_id,
              actor_id: scope.user_id,
              operation: operation,
              key: command["key"],
              digest: digest,
              ticket_id: ticket.id,
              result: value
            })

            value
          end
        end)

      if match?({:ok, _}, result) do
        Phoenix.PubSub.broadcast(
          Instantflow.PubSub,
          "organization:#{actor.organization_id}",
          :permissions_changed
        )
      end

      result
    else
      {:error, :invalid_command}
    end
  end

  def command(_, _), do: {:error, :invalid_command}

  def controls(actor, ticket_id, search \\ "") when is_binary(search) do
    Tenant.read(
      actor,
      fn scope ->
        ticket = Repo.get(Ticket, ticket_id) || Repo.rollback(:not_found)
        version = Repo.get!(Version, ticket.workflow_version_id)

        specs =
          Enum.filter(
            Map.get(version.definition, "participants", []),
            &manage?(scope, ticket, version, &1["key"])
          )

        query = String.slice(String.trim(search), 0, 100)

        controls =
          Enum.map(specs, fn spec ->
            candidates =
              Repo.all(
                from [m, u] in candidate_query(scope, version, spec["key"]),
                  left_join: r in Relationship,
                  on:
                    r.membership_id == m.id and r.ticket_id == ^ticket.id and
                      r.relationship == ^spec["key"],
                  where:
                    is_nil(r.id) and
                      (fragment("strpos(lower(?), lower(?)) > 0", u.name, ^query) or
                         fragment("strpos(lower(?), lower(?)) > 0", u.email, ^query)),
                  distinct: m.id,
                  order_by: m.id,
                  limit: 25,
                  select: {u.name, m.id}
              )

            %{id: spec["key"], key: spec["key"], label: spec["label"], candidates: candidates}
          end)

        relationships =
          Enum.flat_map(specs, fn spec ->
            Repo.all(
              from r in Relationship,
                join: m in assoc(r, :membership),
                join: u in assoc(m, :user),
                where:
                  r.organization_id == ^scope.organization_id and r.ticket_id == ^ticket.id and
                    r.relationship == ^spec["key"] and is_nil(r.legacy_guardian_link_id),
                order_by: r.id,
                limit: 100,
                select: %{
                  id: r.id,
                  key: r.relationship,
                  membership_id: m.id,
                  name: u.name,
                  status: r.status,
                  revision: r.revision
                }
            )
          end)

        %{controls: controls, relationships: relationships}
      end,
      %{controls: [], relationships: []}
    )
  end

  defp participant_roles(version, key) do
    spec = Enum.find(version.definition["participants"], &(&1["key"] == key))

    case spec["candidate_roles"] do
      roles when is_list(roles) ->
        Enum.flat_map(roles, &Map.get(version.bindings["roles"], &1, [])) |> Enum.uniq()

      nil ->
        # Previously pinned Sprint 09 versions keep their original picker contract.
        # New publication requires explicit eligibility, independently of access.
        legacy_participant_roles(version, key)
    end
  end

  defp legacy_participant_roles(version, key) do
    actors =
      Enum.flat_map(version.definition["sections"], & &1["access"]) ++
        Enum.flat_map(version.definition["transitions"], & &1["actors"])

    actors
    |> Enum.filter(&(&1["scope"] == "participant" and &1["relationship"] == key))
    |> Enum.flat_map(&Map.get(version.bindings["roles"], &1["role"], []))
    |> Enum.uniq()
  end

  defp candidate_query(scope, version, key) do
    roles = participant_roles(version, key)

    from m in Membership,
      join: u in assoc(m, :user),
      left_join: g in Instantflow.Access.Grant,
      on: g.membership_id == m.id and g.organization_id == m.organization_id,
      where:
        m.organization_id == ^scope.organization_id and m.active and u.active and
          u.id != ^scope.user_id and (m.role in ^roles or g.role in ^roles)
  end

  @doc false
  def manage?(scope, ticket, version, key) do
    spec = Enum.find(Map.get(version.definition, "participants", []), &(&1["key"] == key))
    spec != nil and Enum.any?(spec["managers"], &Policy.actor?(scope, ticket, version, &1))
  end

  @doc "Only call inside the shared tenant authorization gate."
  def linked?(scope, ticket, version, key) do
    Enum.any?(Map.get(version.definition, "participants", []), &(&1["key"] == key)) and
      Repo.exists?(
        from r in Relationship,
          where:
            r.organization_id == ^scope.organization_id and
              r.workflow_id == ^ticket.workflow_id and r.ticket_id == ^ticket.id and
              r.membership_id == ^scope.id and r.relationship == ^key and
              r.status == "verified" and not is_nil(r.verified_at)
      )
  end

  defp apply!(scope, ticket, member, command) do
    relationship =
      Repo.one(
        from r in Relationship,
          where:
            r.ticket_id == ^ticket.id and r.membership_id == ^member.id and
              r.relationship == ^command["relationship"],
          lock: "FOR UPDATE"
      )

    if relationship && relationship.legacy_guardian_link_id,
      do: Repo.rollback(:legacy_relationship)

    case command["operation"] do
      "create" ->
        if relationship, do: Repo.rollback(:already_exists)
        unless command["expected_revision"] == 0, do: Repo.rollback(:conflict)

        if Repo.aggregate(from(r in Relationship, where: r.ticket_id == ^ticket.id), :count) >=
             100,
           do: Repo.rollback(:quota)

        Repo.insert!(%Relationship{
          organization_id: scope.organization_id,
          workflow_id: ticket.workflow_id,
          ticket_id: ticket.id,
          membership_id: member.id,
          relationship: command["relationship"]
        })

      operation ->
        unless relationship, do: Repo.rollback(:not_found)

        unless relationship.revision == command["expected_revision"],
          do: Repo.rollback(:conflict)

        if operation == "verify" and scope.user_id == member.user_id,
          do: Repo.rollback(:self_verification)

        relationship
        |> Ecto.Changeset.change(
          status: if(operation == "verify", do: "verified", else: "revoked"),
          verified_at:
            if(operation == "verify", do: DateTime.utc_now() |> DateTime.truncate(:second)),
          verified_by_id: scope.user_id,
          revision: relationship.revision + 1
        )
        |> Repo.update!()
    end
  end

  defp valid_command?(c) do
    Enum.sort(Map.keys(c)) ==
      ~w(expected_revision key membership_id operation relationship ticket_id) and
      c["operation"] in ~w(create verify revoke) and
      is_binary(c["key"]) and byte_size(c["key"]) in 1..128 and
      is_binary(c["relationship"]) and
      Regex.match?(~r/^[a-z][a-z0-9_]{0,63}$/, c["relationship"]) and
      is_integer(c["ticket_id"]) and c["ticket_id"] in 1..9_223_372_036_854_775_807 and
      is_integer(c["membership_id"]) and c["membership_id"] in 1..9_223_372_036_854_775_807 and
      is_integer(c["expected_revision"]) and c["expected_revision"] >= 0
  end
end
