defmodule Instantflow.Enrollment do
  @moduledoc "School enrollment boundary. Guardians receive an explicit projection, never the internal runtime projection."
  import Ecto.Query
  alias Instantflow.{Access, Identity, Repo, Tenant, WorkflowCatalog, WorkflowRuntime}
  alias Instantflow.Enrollment.{GuardianLink, Record}
  alias Instantflow.WorkflowRuntime.{Section, Ticket}
  alias Instantflow.WorkflowCatalog.Version

  @statuses %{
    "draft" => "Preencha os dados e envie os documentos",
    "documents" => "Documentos em verificação",
    "correction" => "Correção solicitada: revise os dados e documentos",
    "academic" => "Matrícula em análise",
    "payment" => "Aguardando pagamento simulado",
    "provisioning" => "Preparando acesso simulado",
    "complete" => "Matrícula concluída"
  }

  def staff?(actor), do: actor.role != "parent" and Access.role?(actor, ["admin", "admissions"])

  def install(actor, departments) do
    definition =
      File.read!(Application.app_dir(:instantflow, "priv/workflows/enrollment.json"))
      |> Jason.decode!()

    bindings = %{
      "roles" => %{
        "guardian" => ["parent"],
        "admissions" => ["admissions", "admin"],
        "academic" => ["head"],
        "finance" => ["finance"],
        "it" => ["it"]
      },
      "departments" => departments
    }

    WorkflowCatalog.publish(actor, definition, bindings)
  end

  def create(actor, workflow_id, key) do
    Tenant.transaction(actor, fn a ->
      require_staff!(a)

      version =
        Repo.one(
          from v in Version,
            where: v.workflow_id == ^workflow_id,
            order_by: [desc: v.number],
            limit: 1
        )

      unless version && version.definition["template_key"] == "enrollment",
        do: Repo.rollback(:forbidden)

      result =
        unwrap!(
          WorkflowRuntime.command(a, %{
            "operation" => "create",
            "workflow_id" => workflow_id,
            "key" => key
          })
        )

      enrollment =
        Repo.get_by(Record, ticket_id: result["ticket_id"]) ||
          Repo.insert!(%Record{
            organization_id: a.organization_id,
            ticket_id: result["ticket_id"]
          })

      require_record_staff!(a, enrollment)
      enrollment
    end)
  end

  def invite(actor, id, email) do
    Tenant.transaction(actor, fn a ->
      require_staff!(a)
      enrollment = record!(a, id)
      require_record_staff!(a, enrollment)

      unwrap!(
        Identity.invite(a, %{
          "email" => email,
          "role" => "parent",
          "department_id" => a.department_id,
          "enrollment_id" => enrollment.id
        })
      )
    end)
  end

  def verify(actor, link_id, verified) when is_boolean(verified) do
    Tenant.authorize_change(actor, fn a ->
      require_staff!(a)
      link = Repo.get_by(GuardianLink, id: link_id, organization_id: a.organization_id)
      unless link, do: Repo.rollback(:not_found)
      require_record_staff!(a, record!(a, link.enrollment_id))

      link =
        Repo.update!(
          Ecto.Changeset.change(link,
            active: verified,
            verified_at: if(verified, do: now()),
            verified_by_id: a.user_id
          )
        )

      audit(a, "guardian_verification", "guardian:#{link.id}:#{verified}")

      Phoenix.PubSub.broadcast(
        Instantflow.PubSub,
        "organization:#{a.organization_id}:user:#{Repo.get!(Instantflow.Identity.Membership, link.membership_id).user_id}",
        :permissions_changed
      )

      link
    end)
  end

  # Called only inside an established tenant transaction. A foreign or unverified link never grants access.
  def guardian?(actor, ticket_id) do
    Instantflow.WorkflowRuntime.LegacyAccess.guardian_relationship?(actor, ticket_id)
  end

  def list(actor) do
    Tenant.read(
      actor,
      fn a ->
        Repo.all(
          from e in Record, where: e.organization_id == ^a.organization_id, order_by: [desc: e.id]
        )
        |> Enum.filter(&(record_staff?(a, &1) or guardian?(a, &1.ticket_id)))
        |> Enum.map(&project(a, &1))
      end,
      []
    )
  end

  def get(actor, id) do
    Tenant.transaction(actor, fn a ->
      e = record!(a, id)
      unless record_staff?(a, e) or guardian?(a, e.ticket_id), do: Repo.rollback(:not_found)
      project(a, e)
    end)
  end

  def guardians(actor, id) do
    Tenant.read(
      actor,
      fn a ->
        require_staff!(a)
        e = record!(a, id)
        require_record_staff!(a, e)

        Repo.all(
          from g in GuardianLink, where: g.enrollment_id == ^e.id, preload: [membership: :user]
        )
      end,
      []
    )
  end

  def public_message(actor, id, message) when is_binary(message) and byte_size(message) <= 2000 do
    Tenant.transaction(actor, fn a ->
      require_staff!(a)
      e = record!(a, id)
      require_record_staff!(a, e)
      Repo.update!(Ecto.Changeset.change(e, public_message: message))
      audit(a, "parent_message_published", "enrollment:#{e.id}")
      :ok
    end)
  end

  def documents(actor, id) do
    Tenant.read(
      actor,
      fn a ->
        e = record!(a, id)
        unless record_staff?(a, e) or guardian?(a, e.ticket_id), do: Repo.rollback(:not_found)
        Instantflow.PrivateDocuments.list(a, e.ticket_id)
      end,
      []
    )
  end

  def upload(actor, id, filename, bytes) do
    Tenant.transaction(actor, fn a ->
      e = record!(a, id)
      unless record_staff?(a, e) or guardian?(a, e.ticket_id), do: Repo.rollback(:not_found)

      unwrap!(
        Instantflow.PrivateDocuments.upload(
          a,
          e.ticket_id,
          "application",
          "document",
          filename,
          bytes
        )
      )
    end)
  end

  def save(actor, id, values, stage_revision, section_revision, key) do
    Tenant.transaction(actor, fn a ->
      e = record!(a, id)
      unless guardian?(a, e.ticket_id), do: Repo.rollback(:not_found)

      unwrap!(
        WorkflowRuntime.command(a, %{
          "operation" => "save_section",
          "ticket_id" => e.ticket_id,
          "section" => "application",
          "values" => values,
          "expected_stage_revision" => stage_revision,
          "expected_section_revision" => section_revision,
          "key" => key
        })
      )
    end)
  end

  def submit(actor, id, revision, section_revision, key) do
    Tenant.transaction(actor, fn a ->
      e = record!(a, id)
      unless guardian?(a, e.ticket_id), do: Repo.rollback(:not_found)
      ticket = Repo.get!(Ticket, e.ticket_id)
      edge = if ticket.stage == "correction", do: "resubmit", else: "submit"

      unwrap!(
        WorkflowRuntime.command(a, %{
          "operation" => "transition",
          "ticket_id" => e.ticket_id,
          "transition" => edge,
          "expected_revision" => revision,
          "section_revisions" => %{"application" => section_revision},
          "key" => key
        })
      )
    end)
  end

  defp project(actor, e) do
    t = Repo.get!(Ticket, e.ticket_id)
    s = Repo.get_by!(Section, ticket_id: t.id, key: "application")
    # Allowlist only. No internal history, staff IDs, assignment, assessments, or outbox.
    %{
      id: e.id,
      ticket_id: if(staff?(actor), do: t.id),
      status: Map.get(@statuses, t.stage, "Matrícula em análise"),
      public_message: e.public_message,
      values: Map.take(s.values, ~w(student_name guardian_name school_year document)),
      editable: t.stage in ~w(draft correction),
      revision: t.revision,
      stage_revision: t.stage_revision,
      section_revision: s.revision
    }
  end

  defp record!(a, id) do
    Repo.get_by(Record, id: id, organization_id: a.organization_id) || Repo.rollback(:not_found)
  end

  defp record_staff?(a, e) do
    t = Repo.get!(Ticket, e.ticket_id)
    v = Repo.get!(Version, t.workflow_version_id)
    s = Enum.find(v.definition["sections"], &(&1["key"] == "application"))
    staff?(a) and s != nil and Instantflow.WorkflowRuntime.Policy.section?(a, t, v, s, :read)
  end

  defp require_record_staff!(a, e), do: unless(record_staff?(a, e), do: Repo.rollback(:forbidden))
  defp require_staff!(a), do: unless(staff?(a), do: Repo.rollback(:forbidden))
  defp unwrap!({:ok, result}), do: result
  defp unwrap!({:error, reason}), do: Repo.rollback(reason)
  defp now, do: DateTime.utc_now(:second)

  defp audit(a, operation, key),
    do:
      Repo.insert!(%Instantflow.Organizations.Event{
        organization_id: a.organization_id,
        actor_id: a.user_id,
        operation: operation,
        key: key <> ":" <> Ecto.UUID.generate()
      })
end
