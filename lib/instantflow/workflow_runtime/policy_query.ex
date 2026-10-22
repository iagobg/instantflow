defmodule Instantflow.WorkflowRuntime.PolicyQuery do
  @moduledoc """
  Compiles pinned record policies into database predicates before pagination.

  Call only with a freshly loaded scope inside Tenant's shared authorization
  gate. No record values are needed to compile a policy. Unsupported scopes
  deny access. Keep outcome parity with Policy in the query acceptance tests.
  """
  import Ecto.Query
  alias Instantflow.Access
  alias Instantflow.Collaboration.Assignment
  alias Instantflow.Participants.Relationship

  def discover(scope, version) do
    if Instantflow.WorkflowRuntime.LegacyAccess.parent_portal?(scope, version) do
      dynamic(false)
    else
      version.definition["sections"]
      |> Enum.reduce(dynamic(false), fn section, acc ->
        rule = section(scope, version, section)
        dynamic(^acc or ^rule)
      end)
    end
  end

  def section(scope, version, section) do
    section["access"]
    |> Enum.filter(& &1["read"])
    |> Enum.reduce(dynamic(false), fn spec, acc ->
      rule = actor(scope, version, spec)
      dynamic(^acc or ^rule)
    end)
  end

  def actor(scope, version, spec) do
    profiles =
      Enum.filter(
        Access.profiles(scope),
        &(&1.role in Map.get(version.bindings["roles"], spec["role"], []))
      )

    if profiles == [] do
      dynamic(false)
    else
      case spec["scope"] do
        "requester" ->
          dynamic([ticket: t], t.requester_id == ^scope.user_id)

        "assigned_department" ->
          departments = Enum.map(profiles, & &1.department_id) |> Enum.reject(&is_nil/1)
          dynamic([ticket: t], t.assigned_department_id in ^departments)

        "workflow_department" ->
          department = version.bindings["departments"][spec["department_binding"]]
          dynamic(^Enum.any?(profiles, &(&1.department_id == department)))

        "participant" ->
          participant(scope, version, spec["relationship"])

        "guardian" ->
          if not Instantflow.WorkflowRuntime.LegacyAccess.legacy_definition?(version.definition),
            do: dynamic(false),
            else: relationship(scope, "legacy_guardian", true)

        "assigned_user" ->
          assignment(scope, version, spec["assignment_key"])

        _ ->
          dynamic(false)
      end
    end
  end

  defp participant(scope, version, key) do
    if Enum.any?(Map.get(version.definition, "participants", []), &(&1["key"] == key)),
      do: relationship(scope, key, false),
      else: dynamic(false)
  end

  defp relationship(scope, key, legacy?) do
    query =
      from r in Relationship,
        where:
          r.organization_id == ^scope.organization_id and r.membership_id == ^scope.id and
            r.ticket_id == parent_as(:ticket).id and
            r.workflow_id == parent_as(:ticket).workflow_id and r.relationship == ^key and
            r.status == "verified" and not is_nil(r.verified_at)

    query =
      if legacy?, do: where(query, [r], not is_nil(r.legacy_guardian_link_id)), else: query

    dynamic(exists(subquery(query)))
  end

  defp assignment(scope, version, key) do
    section = Enum.find(version.definition["sections"], &(&1["key"] == key))
    spec = section && section["assignment"]

    eligible? =
      spec && scope.active && scope.role != "parent" &&
        Enum.any?(Access.profiles(scope), fn profile ->
          profile.role in version.bindings["roles"][spec["role"]] and
            profile.department_id == version.bindings["departments"][spec["department_binding"]]
        end)

    if eligible? do
      query =
        from a in Assignment,
          where:
            a.organization_id == ^scope.organization_id and a.membership_id == ^scope.id and
              a.ticket_id == parent_as(:ticket).id and a.section_key == ^key

      dynamic(exists(subquery(query)))
    else
      dynamic(false)
    end
  end
end
