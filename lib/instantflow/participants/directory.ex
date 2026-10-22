defmodule Instantflow.Participants.Directory do
  @moduledoc """
  Bounded record-local references to verified participants or authenticated subjects.

  A reference stores one relationship ID, never a user ID. It grants no target
  access. Managers may resolve that declared relationship's verified members;
  other actors may resolve only themselves. Section policy applies independently.
  """
  import Ecto.Query
  alias Instantflow.{Participants, Repo, Tenant}
  alias Instantflow.Identity.{Membership, User}
  alias Instantflow.Participants.Relationship
  alias Instantflow.WorkflowCatalog.Version
  alias Instantflow.WorkflowRuntime.{Policy, Section, Ticket}

  def options(scope, ticket_id, section_key, field_key, query \\ "")

  def options(scope, ticket_id, section_key, field_key, query)
      when is_binary(query) do
    Tenant.read(
      scope,
      fn actor ->
        ticket = Repo.get(Ticket, ticket_id) || Repo.rollback(:not_found)
        version = Repo.get!(Version, ticket.workflow_version_id)
        section = Enum.find(version.definition["sections"], &(&1["key"] == section_key))
        field = section && Enum.find(section["fields"], &(&1["key"] == field_key))
        stored = Repo.get_by(Section, ticket_id: ticket.id, key: section_key)

        if field && stored,
          do:
            options_scoped(
              actor,
              ticket,
              version,
              section,
              field,
              stored.values[field_key],
              query
            ),
          else: []
      end,
      []
    )
  end

  def options(_, _, _, _, _), do: []

  def validate_values!(actor, ticket, version, section, values) do
    for field <- section["fields"],
        field["type"] == "directory_reference",
        value = values[field["key"]],
        not is_nil(value) do
      query = authorized_query(actor, ticket, version, section, field, :edit)

      unless query && is_integer(value) && Repo.exists?(from r in query, where: r.id == ^value),
        do: Repo.rollback(:invalid_reference)
    end
  end

  def require_current!(ticket, version, sections) do
    for section <- version.definition["sections"],
        field <- section["fields"],
        field["type"] == "directory_reference",
        spec = field["reference"],
        not is_nil(spec),
        stored = Enum.find(sections, &(&1.key == section["key"])),
        value = stored.values[field["key"]],
        not is_nil(value) do
      query = base_query(ticket, spec)

      unless is_integer(value) && Repo.exists?(from r in query, where: r.id == ^value),
        do: Repo.rollback(:invalid_reference)
    end
  end

  @doc false
  def project(actor, ticket, version, sections, readable) do
    Enum.reduce(readable, %{options: %{}, labels: %{}}, fn section, result ->
      stored = Enum.find(sections, &(&1.key == section["key"]))

      Enum.reduce(section["fields"], result, fn field, result ->
        if field["type"] == "directory_reference" do
          ref = section["key"] <> "." <> field["key"]
          value = stored.values[field["key"]]
          label = selected(actor, ticket, version, section, field, value)
          options = options_scoped(actor, ticket, version, section, field, value, "")

          %{
            options: Map.put(result.options, ref, options),
            labels: Map.put(result.labels, ref, if(label, do: %{value => label}, else: %{}))
          }
        else
          result
        end
      end)
    end)
  end

  defp options_scoped(actor, ticket, version, section, field, value, text) do
    case authorized_query(actor, ticket, version, section, field, :edit) do
      nil ->
        []

      query ->
        text = String.slice(String.trim(text), 0, 100)

        rows =
          Repo.all(
            from [r, _m, u] in query,
              where: fragment("strpos(lower(?), lower(?)) > 0", u.name, ^text),
              order_by: [asc: u.name, asc: r.id],
              limit: 25,
              select: {u.name, r.id}
          )

        label = selected(actor, ticket, version, section, field, value)

        if label && not Enum.any?(rows, &(elem(&1, 1) == value)),
          do: rows ++ [{label, value}],
          else: rows
    end
  end

  defp selected(_, _, _, _, _, nil), do: nil

  defp selected(actor, ticket, version, section, field, value) do
    query = authorized_query(actor, ticket, version, section, field, :read)

    if query && is_integer(value),
      do: Repo.one(from [r, _m, u] in query, where: r.id == ^value, select: u.name)
  end

  defp authorized_query(
         actor,
         ticket,
         version,
         section,
         %{"type" => "directory_reference", "reference" => spec},
         action
       ) do
    if Policy.section?(actor, ticket, version, section, action) do
      manager? = Participants.manage?(actor, ticket, version, spec["relationship"])

      from [r, m, _u] in base_query(ticket, spec),
        where: r.organization_id == ^actor.organization_id and (^manager? or m.id == ^actor.id)
    end
  end

  defp authorized_query(_, _, _, _, _, _), do: nil

  defp base_query(ticket, spec) do
    from r in Relationship,
      join: m in Membership,
      on: m.id == r.membership_id and m.organization_id == r.organization_id,
      join: u in User,
      on: u.id == m.user_id,
      where:
        r.organization_id == ^ticket.organization_id and r.workflow_id == ^ticket.workflow_id and
          r.ticket_id == ^ticket.id and r.relationship == ^spec["relationship"] and
          is_nil(r.legacy_guardian_link_id) and r.status == "verified" and
          not is_nil(r.verified_at) and
          m.active and u.active
  end
end
