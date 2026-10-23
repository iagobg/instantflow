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

  @doc "Group identical read-policy declarations within a fresh scoped query; never caches authority."
  def groups(versions) do
    versions
    |> Enum.group_by(fn version ->
      {Map.take(
         version.definition,
         ~w(sections participants interface views creation role_requirements)
       ), version.bindings}
    end)
    |> Map.values()
    |> Enum.sort_by(fn group -> group |> Enum.map(& &1.id) |> Enum.min() end)
  end

  def discover(scope, version) do
    version.definition["sections"]
    |> Enum.reduce(dynamic(false), fn section, acc ->
      rule = section(scope, version, section)
      dynamic(^acc or ^rule)
    end)
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

        "assigned_user" ->
          assignment(scope, version, spec["assignment_key"])

        _ ->
          dynamic(false)
      end
    end
  end

  defp participant(scope, version, key) do
    if Enum.any?(Map.get(version.definition, "participants", []), &(&1["key"] == key)),
      do: relationship(scope, key),
      else: dynamic(false)
  end

  defp relationship(scope, key) do
    query =
      from r in Relationship,
        where:
          r.organization_id == ^scope.organization_id and r.membership_id == ^scope.id and
            r.ticket_id == parent_as(:ticket).id and
            r.workflow_id == parent_as(:ticket).workflow_id and r.relationship == ^key and
            r.status == "verified" and not is_nil(r.verified_at)

    dynamic(exists(subquery(query)))
  end

  defp assignment(scope, version, key) do
    section = Enum.find(version.definition["sections"], &(&1["key"] == key))
    spec = section && section["assignment"]

    eligible? =
      spec && scope.active &&
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
