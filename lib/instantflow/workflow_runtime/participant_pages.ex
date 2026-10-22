defmodule Instantflow.WorkflowRuntime.ParticipantPages do
  @moduledoc "Bounded, pinned participant projections and adapters to existing guarded commands."
  import Ecto.Query
  alias Instantflow.{Repo, Tenant, WorkflowRuntime, PrivateDocuments}
  alias Instantflow.WorkflowCatalog.{Definition, Version}
  alias Instantflow.WorkflowCatalog.ParticipantPages, as: Contract
  alias Instantflow.WorkflowRuntime.{Ticket, Section, Event, Policy}
  alias Instantflow.Enrollment.Document

  def route(actor, id) when is_integer(id) and id > 0 do
    Tenant.read(
      actor,
      fn scope ->
        ticket = Repo.get(Ticket, id)
        version = ticket && Repo.get!(Version, ticket.workflow_version_id)

        cond do
          is_nil(version) or Contract.pages(version.definition) == [] ->
            :default

          Instantflow.WorkflowRuntime.ParticipantPolicy.staff_workspace?(scope, version) ->
            :default

          true ->
            case Enum.find(
                   Contract.pages(version.definition),
                   &Instantflow.WorkflowRuntime.ParticipantPolicy.allowed?(
                     scope,
                     ticket,
                     version,
                     &1
                   )
                 ) do
              nil -> :denied
              page -> {:participant, ticket.workflow_id, page["key"]}
            end
        end
      end,
      :denied
    )
  end

  def route(_, _), do: :denied

  def get(actor, workflow_id, page_key, id) do
    Tenant.read(
      actor,
      fn scope ->
        {ticket, version, page} = resolve!(scope, workflow_id, page_key, id, true)
        {:ok, project(scope, ticket, version, page)}
      end,
      {:error, :not_found}
    )
  end

  def save(actor, workflow_id, page_key, id, section_key, values, observed, key) do
    Tenant.transaction(actor, fn scope ->
      {ticket, version, page} = resolve!(scope, workflow_id, page_key, id)
      fields = readable_fields(scope, ticket, version, page)

      allowed =
        for {ref, _field} <- fields,
            String.starts_with?(ref, section_key <> "."),
            do: ref |> String.split(".") |> List.last()

      unless is_map(values) and map_size(values) > 0 and
               Enum.all?(Map.keys(values), &(&1 in allowed)),
             do: Repo.rollback(:forbidden)

      section = Repo.get_by!(Section, ticket_id: ticket.id, key: section_key)

      command = %{
        "operation" => "save_section",
        "ticket_id" => ticket.id,
        "section" => section_key,
        "values" => Map.merge(section.values, values),
        "expected_stage_revision" => observed.stage_revision,
        "expected_section_revision" => observed.section_revision,
        "key" => key
      }

      run!(WorkflowRuntime.command(scope, command))
    end)
  end

  def transition(actor, workflow_id, page_key, id, edge, revision, reason, key) do
    Tenant.transaction(actor, fn scope ->
      {ticket, version, page} = resolve!(scope, workflow_id, page_key, id)
      unless edge in page["participant"]["actions"], do: Repo.rollback(:forbidden)

      readable =
        Enum.filter(
          version.definition["sections"],
          &Policy.section?(scope, ticket, version, &1, :read)
        )
        |> Enum.map(& &1["key"])

      revisions =
        Repo.all(
          from s in Section,
            where: s.ticket_id == ^id and s.key in ^readable,
            select: {s.key, s.revision}
        )
        |> Map.new()

      run!(
        WorkflowRuntime.command(scope, %{
          "operation" => "transition",
          "ticket_id" => id,
          "transition" => edge,
          "expected_revision" => revision,
          "section_revisions" => revisions,
          "reason" => reason,
          "key" => key
        })
      )
    end)
  end

  def upload(actor, workflow_id, page_key, id, ref, filename, bytes, key) do
    Tenant.transaction(actor, fn scope ->
      {ticket, version, page} = resolve!(scope, workflow_id, page_key, id)
      unless ref in document_refs(scope, ticket, version, page), do: Repo.rollback(:forbidden)
      [section, field] = String.split(ref, ".")
      document = run!(PrivateDocuments.upload(scope, id, section, field, filename, bytes, key))
      row = Repo.get_by!(Section, ticket_id: id, key: section)

      if row.values[field] != document.object_key do
        run!(
          WorkflowRuntime.command(scope, %{
            "operation" => "save_section",
            "ticket_id" => id,
            "section" => section,
            "values" => Map.put(row.values, field, document.object_key),
            "expected_stage_revision" => ticket.stage_revision,
            "expected_section_revision" => row.revision,
            "key" => document.object_key <> ":attach"
          })
        )
      end

      document
    end)
  end

  defp run!({:ok, result}), do: result
  defp run!({:error, reason}), do: Repo.rollback(reason)

  defp resolve!(scope, workflow_id, key, id, fallback? \\ false) do
    unless is_integer(workflow_id) and workflow_id > 0 and is_integer(id) and id > 0,
      do: Repo.rollback(:not_found)

    ticket =
      Repo.get_by(Ticket,
        id: id,
        workflow_id: workflow_id,
        organization_id: scope.organization_id
      ) || Repo.rollback(:not_found)

    version = Repo.get!(Version, ticket.workflow_version_id)
    requested = Contract.find(version.definition, key)

    page =
      requested ||
        (fallback? &&
           Enum.find(
             Contract.pages(version.definition),
             &Instantflow.WorkflowRuntime.ParticipantPolicy.allowed?(scope, ticket, version, &1)
           ))

    unless page &&
             Instantflow.WorkflowRuntime.ParticipantPolicy.allowed?(scope, ticket, version, page),
           do: Repo.rollback(:not_found)

    {ticket, version, page}
  end

  defp readable_fields(scope, ticket, version, page) do
    fields = Definition.fields(version.definition)

    for ref <- page["participant"]["fields"],
        readable?(scope, ticket, version, ref),
        into: %{},
        do: {ref, fields[ref]}
  end

  defp document_refs(scope, ticket, version, page),
    do: Enum.filter(page["participant"]["documents"], &readable?(scope, ticket, version, &1))

  defp readable?(scope, ticket, version, ref) do
    [key, _] = String.split(ref, ".")
    section = Enum.find(version.definition["sections"], &(&1["key"] == key))
    section && Policy.section?(scope, ticket, version, section, :read)
  end

  defp project(scope, ticket, version, page) do
    spec = page["participant"]
    fields = readable_fields(scope, ticket, version, page)
    refs = document_refs(scope, ticket, version, page)

    section_keys =
      (Map.keys(fields) ++ refs) |> Enum.map(&(String.split(&1, ".") |> hd())) |> Enum.uniq()

    sections =
      Repo.all(
        from s in Section, where: s.ticket_id == ^ticket.id and s.key in ^section_keys, limit: 50
      )
      |> Map.new(&{&1.key, &1})

    values =
      Enum.map(fields, fn {ref, field} ->
        [section_key, field_key] = String.split(ref, ".")
        row = sections[section_key]
        section = Enum.find(version.definition["sections"], &(&1["key"] == section_key))

        %{
          id: ref,
          ref: ref,
          section: section_key,
          key: field_key,
          label: field["label"],
          type: field["type"],
          options: field["options"] || [],
          value: row && row.values[field_key],
          revision: row && row.revision,
          editable?: Policy.section?(scope, ticket, version, section, :edit)
        }
      end)
      |> Enum.sort_by(& &1.ref)

    actions =
      version.definition["transitions"]
      |> Enum.filter(
        &(&1["key"] in spec["actions"] and Policy.transition?(scope, ticket, version, &1))
      )
      |> Enum.map(&%{id: &1["key"], label: &1["label"], reason?: &1["require_reason"]})

    doc_policy =
      Enum.reduce(refs, dynamic(false), fn ref, acc ->
        [section, field] = String.split(ref, ".")
        dynamic([d], ^acc or (d.section_key == ^section and d.field_key == ^field))
      end)

    documents =
      Repo.all(
        from d in Document,
          where: d.ticket_id == ^ticket.id,
          where: ^doc_policy,
          order_by: [
            asc: fragment("CASE WHEN ? IN ('ready', 'quarantined') THEN 0 ELSE 1 END", d.status),
            desc: d.id
          ],
          limit: 20,
          select: %{
            id: d.id,
            ref: fragment("? || '.' || ?", d.section_key, d.field_key),
            object_key: d.object_key,
            filename: d.filename,
            status: d.status
          }
      )

    # Only selected transition status is released. Actor identities, arbitrary
    # reasons, section changes and delivery payloads are intentionally excluded.
    history =
      if spec["history"] do
        keys =
          version.definition["transitions"]
          |> Enum.filter(
            &(&1["key"] in spec["actions"] and
                Policy.history?(scope, ticket, version, %{operation: &1["key"]}))
          )
          |> Enum.map(& &1["key"])

        Repo.all(
          from e in Event,
            where: e.ticket_id == ^ticket.id and e.operation in ^keys,
            order_by: [desc: e.revision, desc: e.id],
            limit: 50,
            select: %{id: e.id, operation: e.operation, inserted_at: e.inserted_at}
        )
        |> Enum.map(fn event ->
          edge = Enum.find(version.definition["transitions"], &(&1["key"] == event.operation))
          %{id: event.id, label: edge["label"], inserted_at: event.inserted_at}
        end)
      else
        []
      end

    uploads =
      for ref <- refs,
          [section_key, _] = String.split(ref, "."),
          section = Enum.find(version.definition["sections"], &(&1["key"] == section_key)),
          Policy.section?(scope, ticket, version, section, :edit),
          do: {Definition.fields(version.definition)[ref]["label"], ref}

    %{
      id: ticket.id,
      workflow_id: ticket.workflow_id,
      page_key: page["key"],
      label: page["label"],
      revision: ticket.revision,
      stage_revision: ticket.stage_revision,
      status:
        if(spec["status"],
          do: Enum.find(version.definition["stages"], &(&1["key"] == ticket.stage))["label"]
        ),
      fields: values,
      actions: actions,
      documents: documents,
      history: history,
      messages:
        Instantflow.Delivery.Curated.inbox(scope, ticket.workflow_id, %{
          "ticket_id" => ticket.id,
          "keys" => spec["messages"] || []
        }).rows,
      uploads: uploads
    }
  end
end
