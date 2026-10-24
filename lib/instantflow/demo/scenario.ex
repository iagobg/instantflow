defmodule Instantflow.Demo.Scenario do
  @moduledoc false
  import Ecto.Query
  alias Instantflow.{Access, Identity, Repo, Tenant, WorkflowCatalog, WorkflowRuntime}
  alias Instantflow.Identity.{Membership, User}
  alias Instantflow.WorkflowCatalog.{Retirement, Version, Workflow}
  alias Instantflow.WorkflowRuntime.Receipt

  def ensure(operator, schema, keys, attrs) do
    operator.get_by(schema, keys) ||
      operator.insert!(struct(schema, Map.merge(Map.new(keys), attrs)))
  end

  def member!(operator, org, department_id, email, name, role, password) do
    user =
      operator.get_by(User, email: email) ||
        operator.insert!(User.changeset(%User{email: email}, %{name: name, password: password}))

    member =
      ensure(operator, Membership, [organization_id: org.id, user_id: user.id], %{
        department_id: department_id,
        role: role
      })

    unless member.active and member.role == role and user.active,
      do: raise("Demo identity changed or revoked: #{email}; not reactivating it")

    Identity.scope(user.id, org.id) || raise("Demo identity unavailable: #{email}")
  end

  def grant!(admin, member, department, role) do
    exists? =
      Tenant.read(admin, fn _ ->
        Repo.exists?(
          from g in Access.Grant,
            where:
              g.membership_id == ^member.id and
                g.department_id == ^department and g.role == ^role
        )
      end)

    unless exists?, do: ok!(Access.grant(admin, member.id, department, role))
  end

  def version!(actor, workflow_key, bindings, options \\ []) do
    definition = Keyword.get(options, :definition, Instantflow.Examples.definition(workflow_key))
    upgrade_from = Keyword.get(options, :upgrade_from)

    ok!(
      Tenant.transaction(actor, fn _ ->
        Repo.query!("SELECT pg_advisory_xact_lock($1)", [actor.organization_id])

        latest =
          Repo.one(
            from v in Version,
              join: w in Workflow,
              on: w.id == v.workflow_id,
              where: w.key == ^workflow_key,
              order_by: [desc: v.number],
              limit: 1
          )

        cond do
          is_nil(latest) or Retirement.retired?(latest.id) or
              (not is_nil(upgrade_from) and latest.definition == upgrade_from and
                 latest.bindings == bindings) ->
            ok!(
              WorkflowCatalog.publish(
                actor,
                definition,
                bindings,
                if(latest, do: latest.number, else: 0)
              )
            )

          latest.definition == definition and latest.bindings == bindings ->
            latest

          true ->
            raise(
              "Demo publication differs from the fixture; preserve its pins and review explicitly"
            )
        end
      end)
    )
  end

  def save!(actor, id, section_key, values, key) do
    data = ok!(WorkflowRuntime.get(actor, id))
    section = Enum.find(data.sections, &(&1.key == section_key))

    ok!(
      WorkflowRuntime.command(actor, %{
        "operation" => "save_section",
        "ticket_id" => id,
        "section" => section_key,
        "values" => values,
        "key" => key,
        "expected_stage_revision" => data.ticket.stage_revision,
        "expected_section_revision" => section.revision
      })
    )
  end

  def transition!(actor, id, edge, key, reason \\ nil) do
    data = ok!(WorkflowRuntime.get(actor, id))

    ok!(
      WorkflowRuntime.command(actor, %{
        "operation" => "transition",
        "ticket_id" => id,
        "transition" => edge,
        "key" => key,
        "reason" => reason,
        "expected_revision" => data.ticket.revision,
        "section_revisions" => Map.new(data.sections, &{&1.key, &1.revision})
      })
    )
  end

  def ok!({:ok, value}), do: value
  def ok!({:error, reason}), do: raise("Demo fixture failed: #{inspect(reason)}")
  # Commit the complete synthetic history once; a rerun preserves subsequent edits.
  def case!(actor, version, key, populate) do
    ok!(
      Tenant.transaction(actor, fn _ ->
        Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [key])

        unless Repo.get_by(Receipt,
                 organization_id: actor.organization_id,
                 actor_id: actor.user_id,
                 operation: "create",
                 key: key
               ) do
          result =
            ok!(
              WorkflowRuntime.command(actor, %{
                "operation" => "create",
                "workflow_id" => version.workflow_id,
                "key" => key
              })
            )

          populate.(result["ticket_id"])
        end
      end)
    )
  end

  # Only process this new fixture's simulated intent, never the tenant's backlog.
  def delivery!(actor, id, kind, retry?) do
    message =
      Tenant.read(actor, fn _ ->
        Repo.one!(
          from m in Instantflow.Delivery.Message,
            where: m.ticket_id == ^id and m.kind == ^kind
        )
      end)

    ok!(Instantflow.Delivery.process(actor.organization_id, message.id))

    if retry? do
      ok!(Instantflow.Delivery.retry(actor, message.id))
      ok!(Instantflow.Delivery.process(actor.organization_id, message.id))
    end
  end
end
