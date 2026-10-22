defmodule Instantflow.Collaboration.Assignments do
  @moduledoc "Named local section assignments. Assignment changes take the exclusive authorization gate."
  import Ecto.Query
  alias Instantflow.{Access, Repo}
  alias Instantflow.Collaboration.Assignment
  alias Instantflow.Identity.Membership
  alias Instantflow.WorkflowRuntime.Policy

  def manager?(actor, ticket, version, section) do
    spec = section["assignment"]
    spec && Enum.any?(spec["managers"], &Policy.actor?(actor, ticket, version, &1))
  end

  def assigned?(actor, ticket, version, key) do
    section = Enum.find(version.definition["sections"], &(&1["key"] == key))
    spec = section && section["assignment"]

    not is_nil(spec) and eligible?(actor, version, spec) and
      Repo.exists?(
        from a in Assignment,
          where:
            a.ticket_id == ^ticket.id and a.section_key == ^key and a.membership_id == ^actor.id
      )
  end

  def controls_for(actor, id, search) do
    Instantflow.Tenant.read(
      actor,
      fn fresh ->
        ticket = Repo.get(Instantflow.WorkflowRuntime.Ticket, id) || Repo.rollback(:not_found)
        version = Repo.get!(Instantflow.WorkflowCatalog.Version, ticket.workflow_version_id)
        controls(fresh, ticket, version, search)
      end,
      []
    )
  end

  def controls(actor, ticket, version, search \\ "") do
    search = if is_binary(search), do: String.slice(search, 0, 100), else: ""

    Enum.flat_map(version.definition["sections"], fn section ->
      if manager?(actor, ticket, version, section) do
        spec = section["assignment"]

        roles = version.bindings["roles"][spec["role"]]
        department = version.bindings["departments"][spec["department_binding"]]
        legacy? = Instantflow.WorkflowRuntime.LegacyAccess.legacy_definition?(version.definition)

        candidates =
          Repo.all(
            from m in Membership,
              join: u in Instantflow.Identity.User,
              on: u.id == m.user_id,
              left_join: g in Instantflow.Access.Grant,
              on: g.membership_id == m.id,
              where:
                m.active and u.active and
                  (not (^legacy?) or m.role != "parent") and
                  ((m.role in ^roles and m.department_id == ^department) or
                     (g.role in ^roles and g.department_id == ^department)) and
                  fragment("strpos(lower(?), lower(?)) > 0", u.name, ^search),
              distinct: m.id,
              order_by: m.id,
              limit: 100,
              preload: [:user]
          )

        assignment = Repo.get_by(Assignment, ticket_id: ticket.id, section_key: section["key"])

        [
          %{
            id: section["key"],
            label: section["label"],
            options: Enum.map(candidates, &{&1.user.name, &1.id}),
            membership_id: assignment && assignment.membership_id,
            editable?: ticket.stage in spec["stages"],
            revocable?: not is_nil(assignment)
          }
        ]
      else
        []
      end
    end)
  end

  def apply!(actor, ticket, version, command) do
    section = Enum.find(version.definition["sections"], &(&1["key"] == command["section"]))
    unless section && manager?(actor, ticket, version, section), do: Repo.rollback(:forbidden)
    spec = section["assignment"]

    unless is_nil(command["membership_id"]) or ticket.stage in spec["stages"],
      do: Repo.rollback(:forbidden)

    unless ticket.revision == command["expected_revision"], do: Repo.rollback(:conflict)
    reason = command["reason"]

    unless is_binary(reason) and String.length(String.trim(reason)) in 1..2000,
      do: Repo.rollback(:reason_required)

    member_id = command["membership_id"]

    if member_id do
      member =
        Repo.get_by(Membership,
          id: member_id,
          organization_id: actor.organization_id,
          active: true
        )

      unless member && eligible?(Access.load(member), version, spec),
        do: Repo.rollback(:invalid_assignee)

      unless Repo.get!(Instantflow.Identity.User, member.user_id).active,
        do: Repo.rollback(:invalid_assignee)
    end

    existing = Repo.get_by(Assignment, ticket_id: ticket.id, section_key: section["key"])
    if existing, do: Repo.delete!(existing)

    if member_id,
      do:
        Repo.insert!(%Assignment{
          organization_id: actor.organization_id,
          ticket_id: ticket.id,
          section_key: section["key"],
          membership_id: member_id
        })

    updated = ticket |> Ecto.Changeset.change(revision: ticket.revision + 1) |> Repo.update!()
    previous_id = if existing, do: to_string(existing.membership_id), else: "nenhum"
    next_id = if member_id, do: to_string(member_id), else: "nenhum"
    {updated, "Responsável local #{previous_id} → #{next_id}. " <> reason}
  end

  defp eligible?(actor, version, spec) do
    actor.active && not Instantflow.WorkflowRuntime.LegacyAccess.parent_portal?(actor, version) &&
      Enum.any?(
        Access.profiles(actor),
        &(&1.role in version.bindings["roles"][spec["role"]] &&
            &1.department_id == version.bindings["departments"][spec["department_binding"]])
      )
  end
end
