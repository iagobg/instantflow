defmodule Instantflow.PrivateDocuments do
  @moduledoc "Bounded private database objects. No public URLs, client paths, or caller-supplied ready flags."
  import Ecto.Query
  alias Instantflow.{Repo, Tenant}
  alias Instantflow.Enrollment.Document
  alias Instantflow.WorkflowCatalog.Version
  alias Instantflow.WorkflowRuntime.Ticket
  alias Instantflow.PrivateDocuments.Policy
  @max_size 5_242_880

  def upload(
        actor,
        ticket_id,
        section_key,
        field_key,
        filename,
        bytes,
        key \\ Ecto.UUID.generate()
      )

  def upload(actor, ticket_id, section_key, field_key, filename, bytes, key)
      when is_binary(bytes) and byte_size(bytes) in 1..@max_size do
    Tenant.transaction(actor, fn a ->
      {ticket, version} = ticket!(a, ticket_id)
      section = section!(version, section_key, field_key)

      unless allowed?(a, ticket, version, section, field_key, :edit),
        do: Repo.rollback(:forbidden)

      mutate!(
        a,
        ticket,
        section,
        field_key,
        "upload",
        key,
        {filename, :crypto.hash(:sha256, bytes)},
        fn ->
          count =
            Repo.aggregate(
              from(d in Document,
                where: d.ticket_id == ^ticket.id and d.status in ["quarantined", "ready"]
              ),
              :count
            )

          if count >= 20, do: Repo.rollback(:quota)
          type = media_type(bytes)

          unless type && safe_filename?(filename) &&
                   Policy.file?(section, field_key, type, byte_size(bytes)),
                 do: Repo.rollback(:invalid_file)

          d =
            Repo.insert!(%Document{
              organization_id: a.organization_id,
              ticket_id: ticket.id,
              section_key: section_key,
              field_key: field_key,
              object_key: Ecto.UUID.generate(),
              filename: filename,
              media_type: type,
              content: bytes,
              sha256: :crypto.hash(:sha256, bytes),
              size: byte_size(bytes),
              uploaded_by_id: a.user_id,
              expires_at: DateTime.add(now(), 30 * 86400)
            })

          audit(a, "document_quarantined", d)
          record_change!(a, ticket, section, field_key, "upload")
          metadata(d)
        end
      )
    end)
  end

  def upload(_, _, _, _, _, _, _), do: {:error, :invalid_file}

  # Manual staff review is required even when the bounded format checks pass.
  # This is a synthetic-data demonstration, not an antivirus service.
  def review(actor, key, accept?, receipt_key \\ Ecto.UUID.generate()) when is_boolean(accept?) do
    Tenant.transaction(actor, fn a ->
      d = document!(a, key)
      {ticket, version} = ticket!(a, d.ticket_id)
      d = document!(a, key)
      section = section!(version, d.section_key, d.field_key)

      reviewer? =
        Policy.reviewer?(a, ticket, version, section, d.field_key, d.uploaded_by_id)

      unless reviewer? and allowed?(a, ticket, version, section, d.field_key, :read),
        do: Repo.rollback(:forbidden)

      mutate!(a, ticket, section, d.field_key, "review", receipt_key, {key, accept?}, fn ->
        unless d.status == "quarantined" and DateTime.compare(d.expires_at, now()) == :gt,
          do: Repo.rollback(:invalid_state)

        ready =
          accept? and media_type(d.content) == d.media_type and
            byte_size(d.content) == d.size and
            Policy.file?(section, d.field_key, d.media_type, d.size) and
            :crypto.hash(:sha256, d.content) == d.sha256

        status = if ready, do: "ready", else: "rejected"

        d =
          Repo.update!(
            Ecto.Changeset.change(d,
              status: status,
              reviewed_by_id: a.user_id,
              content: if(ready, do: d.content, else: <<>>)
            )
          )

        audit(a, "document_" <> status, d)
        record_change!(a, ticket, section, d.field_key, status)
        metadata(d)
      end)
    end)
  end

  def delete(actor, key, receipt_key \\ Ecto.UUID.generate()) do
    Tenant.transaction(actor, fn a ->
      d = document!(a, key)
      {ticket, version} = ticket!(a, d.ticket_id)
      d = document!(a, key)
      section = section!(version, d.section_key, d.field_key)

      unless allowed?(a, ticket, version, section, d.field_key, :edit),
        do: Repo.rollback(:forbidden)

      mutate!(a, ticket, section, d.field_key, "delete", receipt_key, key, fn ->
        Repo.update!(Ecto.Changeset.change(d, status: "deleted", content: <<>>))
        audit(a, "document_deleted", d)
        record_change!(a, ticket, section, d.field_key, "delete")
        :ok
      end)
    end)
  end

  def list(actor, ticket_id) do
    Tenant.read(
      actor,
      fn a ->
        {ticket, version} = ticket!(a, ticket_id)

        Repo.all(from d in Document, where: d.ticket_id == ^ticket.id, order_by: [desc: d.id])
        |> Enum.filter(fn d ->
          allowed?(
            a,
            ticket,
            version,
            section!(version, d.section_key, d.field_key),
            d.field_key,
            :read
          )
        end)
        |> Enum.map(fn d ->
          section = section!(version, d.section_key, d.field_key)

          Map.put(
            metadata(d),
            :can_review,
            Policy.reviewer?(a, ticket, version, section, d.field_key, d.uploaded_by_id)
          )
        end)
      end,
      []
    )
  end

  def download(actor, key) when is_binary(key) do
    Tenant.transaction(actor, fn a ->
      d = document!(a, key)
      {ticket, version} = ticket!(a, d.ticket_id)
      d = document!(a, key)
      section = section!(version, d.section_key, d.field_key)

      unless Policy.download_allowed?(a, ticket, version, section, d.field_key) and ready?(d) and
               Policy.file?(section, d.field_key, d.media_type, d.size),
             do: Repo.rollback(:not_found)

      audit(a, "document_downloaded", d)
      %{filename: d.filename, media_type: d.media_type, content: d.content}
    end)
  end

  def download(_, _), do: {:error, :not_found}

  def purge_expired(organization_id) do
    Tenant.raw(organization_id, fn ->
      archived =
        from t in Ticket,
          join: r in "retired_workflow_versions",
          on: r.version_id == t.workflow_version_id,
          where: t.id == parent_as(:document).ticket_id,
          select: 1

      Repo.update_all(
        from(d in Document,
          as: :document,
          where: d.expires_at <= ^now() and d.status in ["ready", "quarantined"],
          where: not exists(subquery(archived))
        ),
        set: [status: "expired", content: <<>>]
      )
    end)
  end

  # Runtime callers already hold the ticket lock. All object claims are proved again here.
  def validate_values!(actor, ticket, section, values) when is_map(values) do
    for field <- section["fields"],
        field["type"] == "attachment",
        key = values[field["key"]],
        not is_nil(key) do
      d =
        Repo.get_by(Document,
          object_key: key,
          ticket_id: ticket.id,
          organization_id: actor.organization_id,
          section_key: section["key"],
          field_key: field["key"]
        )

      unless d && d.status in ["quarantined", "ready"] &&
               DateTime.compare(d.expires_at, now()) == :gt,
             do: Repo.rollback(:invalid_attachment)
    end
  end

  def validate_values!(_, _, _, _), do: :ok

  def require_ready!(ticket, version, values, required) do
    fields = Instantflow.WorkflowCatalog.Definition.fields(version.definition)

    for ref <- required, fields[ref]["type"] == "attachment" do
      unless ready_ref?(ticket, ref, values[ref]), do: Repo.rollback(:attachment_not_ready)
    end
  end

  def guard_values(ticket, version, values) do
    for {ref, field} <- Instantflow.WorkflowCatalog.Definition.fields(version.definition),
        field["type"] == "attachment",
        reduce: values do
      acc ->
        Map.put(
          acc,
          ref,
          if(ready_ref?(ticket, ref, values[ref]), do: :attachment_ready, else: values[ref])
        )
    end
  end

  defp allowed?(actor, ticket, version, section, field_key, permission) do
    Policy.allowed?(actor, ticket, version, section, field_key, permission)
  end

  defp record_change!(actor, ticket, section, field, operation) do
    if Policy.declaration(section, field) do
      updated = ticket |> Ecto.Changeset.change(revision: ticket.revision + 1) |> Repo.update!()

      Instantflow.WorkflowRuntime.record(
        updated,
        actor,
        "document:" <> operation <> ":" <> section["key"] <> "." <> field,
        ticket.stage,
        nil,
        []
      )
    end
  end

  defp mutate!(actor, ticket, section, field, operation, key, payload, fun) do
    Instantflow.WorkflowCatalog.Retirement.require_active!(ticket.workflow_version_id)

    if Policy.declaration(section, field) do
      unless is_binary(key) and byte_size(key) in 1..128, do: Repo.rollback(:invalid_command)
      operation = "document:" <> operation

      digest =
        :crypto.hash(
          :sha256,
          :erlang.term_to_binary({ticket.id, section["key"], field, operation, payload}, [
            :deterministic
          ])
        )

      receipt =
        Repo.get_by(Instantflow.WorkflowRuntime.Receipt,
          organization_id: actor.organization_id,
          actor_id: actor.user_id,
          operation: operation,
          key: key
        )

      if receipt do
        unless receipt.digest == digest, do: Repo.rollback(:idempotency_mismatch)

        if receipt.result["object_key"],
          do: metadata(document!(actor, receipt.result["object_key"])),
          else: :ok
      else
        result = fun.()
        object_key = if is_map(result), do: result.object_key

        Repo.insert!(%Instantflow.WorkflowRuntime.Receipt{
          organization_id: actor.organization_id,
          actor_id: actor.user_id,
          ticket_id: ticket.id,
          operation: operation,
          key: key,
          digest: digest,
          result: %{"object_key" => object_key}
        })

        result
      end
    else
      fun.()
    end
  end

  defp ready_ref?(ticket, ref, key) when is_binary(key) do
    [section, field] = String.split(ref, ".", parts: 2)

    d =
      Repo.get_by(Document,
        organization_id: ticket.organization_id,
        ticket_id: ticket.id,
        section_key: section,
        field_key: field,
        object_key: key
      )

    d && ready?(d)
  end

  defp ready_ref?(_, _, _), do: false
  defp ready?(d), do: d.status == "ready" and DateTime.compare(d.expires_at, now()) == :gt

  defp ticket!(a, id) do
    t =
      Repo.one(
        from t in Ticket,
          where: t.id == ^id and t.organization_id == ^a.organization_id,
          lock: "FOR UPDATE"
      )

    unless t, do: Repo.rollback(:not_found)
    {t, Repo.get!(Version, t.workflow_version_id)}
  end

  defp section!(version, key, field_key) do
    s = Enum.find(version.definition["sections"], &(&1["key"] == key))

    unless s && Enum.any?(s["fields"], &(&1["key"] == field_key and &1["type"] == "attachment")),
      do: Repo.rollback(:not_found)

    s
  end

  defp document!(a, key),
    do:
      Repo.get_by(Document, object_key: key, organization_id: a.organization_id) ||
        Repo.rollback(:not_found)

  defp metadata(d),
    do:
      Map.take(d, [
        :id,
        :object_key,
        :filename,
        :media_type,
        :size,
        :status,
        :expires_at,
        :section_key,
        :field_key
      ])

  defp safe_filename?(name),
    do:
      is_binary(name) and String.length(name) in 1..160 and
        Regex.match?(~r/^[\p{L}\p{N}_. ()-]+\.(pdf|png|jpg|jpeg)$/iu, name)

  defp media_type(<<"%PDF-", _::binary>> = b),
    do:
      if(
        String.contains?(b, "%%EOF") and
          not Regex.match?(~r/\/(JavaScript|JS|Launch|EmbeddedFile|OpenAction)\b/, b),
        do: "application/pdf"
      )

  defp media_type(<<137, 80, 78, 71, 13, 10, 26, 10, _::binary>> = b),
    do: if(byte_size(b) > 32 and :binary.match(b, "IEND") != :nomatch, do: "image/png")

  defp media_type(<<255, 216, 255, _::binary>> = b),
    do: if(:binary.part(b, byte_size(b) - 2, 2) == <<255, 217>>, do: "image/jpeg")

  defp media_type(_), do: nil
  defp now, do: DateTime.utc_now(:second)

  defp audit(a, operation, d),
    do:
      Repo.insert!(%Instantflow.Organizations.Event{
        organization_id: a.organization_id,
        actor_id: a.user_id,
        operation: operation,
        key: "document:#{d.id}:#{Ecto.UUID.generate()}"
      })
end
