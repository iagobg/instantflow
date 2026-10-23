defmodule Instantflow.Calculations do
  @moduledoc "Durable calculation intents, expiring fenced leases and current-authority result application."
  import Ecto.Query
  alias Instantflow.{Access, Repo, Tenant}
  alias Instantflow.Calculations.{Attempt, Catalogue, Contract, Run, Runner}
  alias Instantflow.WorkflowCatalog.Version
  alias Instantflow.WorkflowRuntime.{Policy, Section, Ticket}

  # Locking the durable switch serializes disablement with queueing/finalization.
  def switch! do
    unless Application.get_env(:instantflow, :calculation_execution, false),
      do: Repo.rollback(:execution_disabled)

    case Repo.query!("SELECT enabled, generation FROM lock_calculation_switch()").rows do
      [[true, generation]] -> generation
      _ -> Repo.rollback(:execution_disabled)
    end
  end

  def enqueue!(_actor, _ticket, _version, _sections, %{"calculation" => nil}), do: :ok

  def enqueue!(actor, ticket, version, sections, transition) do
    if spec = transition["calculation"] do
      generation = switch!()
      Catalogue.permit!(actor, "python_execute")
      {script, review} = Catalogue.resolve!(spec)
      authorize_inputs!(actor, ticket, version, script, spec)
      snapshot = snapshot(spec, sections)

      unless Contract.values?(script.input_schema, snapshot),
        do: Repo.rollback(:invalid_calculation)

      Repo.query!(
        "SELECT pg_advisory_xact_lock(hashtextextended('calculations:' || $1::text, 0))",
        [to_string(actor.organization_id)]
      )

      pending = Repo.aggregate(from(r in Run, where: r.status in ["queued", "running"]), :count)
      if pending >= 20, do: Repo.rollback(:queue_full)

      Repo.insert!(%Run{
        organization_id: actor.organization_id,
        ticket_id: ticket.id,
        script_id: script.id,
        membership_id: actor.id,
        action_key: transition["key"],
        spec: spec,
        snapshot: snapshot,
        revisions: revisions(spec, sections),
        stage: ticket.stage,
        stage_revision: ticket.stage_revision,
        generation: generation,
        review_generation: review.generation
      })
    end

    :ok
  end

  def require!(_ticket, _sections, nil), do: :ok

  def require!(ticket, sections, action) do
    generation = switch!()

    run =
      Repo.one(
        from r in Run,
          where:
            r.ticket_id == ^ticket.id and r.action_key == ^action and
              r.stage_revision == ^ticket.stage_revision and r.status == "succeeded"
      )

    unless run && run.generation == generation && run.revisions == revisions(run.spec, sections),
      do: Repo.rollback(:calculation_required)

    {_script, review} = Catalogue.resolve!(run.spec)
    unless run.review_generation == review.generation, do: Repo.rollback(:calculation_required)
    # A revoked initiating member must invalidate even a previously accepted result.
    actor = actor!(run)
    version = Repo.get!(Version, ticket.workflow_version_id)
    authorize_inputs!(actor, ticket, version, Catalogue.script!(run.script_id), run.spec)
  end

  def claim(organization_id) do
    Tenant.raw(organization_id, fn ->
      generation = switch!()

      Repo.query!(
        "SELECT pg_advisory_xact_lock_shared(hashtextextended('access:' || $1::text, 0))",
        [to_string(organization_id)]
      )

      now = DateTime.utc_now()

      run =
        Repo.one(
          from r in Run,
            where: r.status == "queued" or (r.status == "running" and r.lease_until <= ^now),
            order_by: r.id,
            limit: 1
        )

      unless run, do: Repo.rollback(:empty)

      ticket =
        Repo.one(from t in Ticket, where: t.id == ^run.ticket_id, lock: "FOR UPDATE SKIP LOCKED") ||
          Repo.rollback(:busy)

      Repo.query!(
        "SELECT pg_advisory_xact_lock(hashtextextended('calculations:' || $1::text, 0))",
        [to_string(organization_id)]
      )

      if Repo.exists?(from r in Run, where: r.status == "running" and r.lease_until > ^now),
        do: Repo.rollback(:busy)

      run = Repo.one!(from r in Run, where: r.id == ^run.id, lock: "FOR UPDATE")

      unless run.status == "queued" or
               (run.status == "running" and DateTime.compare(run.lease_until, now) != :gt),
             do: Repo.rollback(:busy)

      sections = Repo.all(from s in Section, where: s.ticket_id == ^ticket.id)
      version = Repo.get!(Version, ticket.workflow_version_id)
      if run.status == "running", do: attempt!(run, "lease_expired")

      cond do
        not current?(run, ticket, version, sections, generation) ->
          Repo.update!(
            Ecto.Changeset.change(run,
              status: "stale",
              diagnostic: "Execução desativada desde a criação."
            )
          )

          :discarded

        run.attempts >= 3 ->
          Repo.update!(
            Ecto.Changeset.change(run,
              status: "failed",
              diagnostic: "Limite de tentativas atingido."
            )
          )

          :discarded

        true ->
          fence = Ecto.UUID.generate()

          run =
            Repo.update!(
              Ecto.Changeset.change(run,
                status: "running",
                fence: fence,
                attempts: run.attempts + 1,
                lease_until: DateTime.add(now, 20, :second)
              )
            )

          {run, Catalogue.script!(run.script_id)}
      end
    end)
  end

  def process(organization_id) do
    with {:ok, {run, script}} <- claim(organization_id) do
      request = Runner.request(script, run.snapshot, run.id, run.fence)
      response = Runner.execute(request)
      finalize(organization_id, run.id, run.fence, request, response)
    end
  end

  def finalize(org, id, fence, _request, response) do
    Tenant.raw(org, fn ->
      generation = switch!()
      # Match authorization-change ordering and freeze current grants during finalization.
      Repo.query!(
        "SELECT pg_advisory_xact_lock_shared(hashtextextended('access:' || $1::text, 0))",
        [to_string(org)]
      )

      original = Repo.get(Run, id) || Repo.rollback(:not_found)
      ticket = Repo.one!(from t in Ticket, where: t.id == ^original.ticket_id, lock: "FOR UPDATE")
      run = Repo.one!(from r in Run, where: r.id == ^id, lock: "FOR UPDATE")

      unless run.status == "running" and run.fence == fence and
               DateTime.compare(run.lease_until, DateTime.utc_now()) == :gt,
             do: Repo.rollback(:stale_attempt)

      sections = Repo.all(from s in Section, where: s.ticket_id == ^ticket.id, lock: "FOR UPDATE")
      version = Repo.get!(Version, ticket.workflow_version_id)
      script = Catalogue.script!(run.script_id)
      fresh = current?(run, ticket, version, sections, generation)
      expected = Runner.request(script, run.snapshot, run.id, run.fence)
      {status, output, diagnostic} = result(expected, response, script, fresh)
      if status == "succeeded", do: apply_output!(run, output, sections)

      Repo.update!(
        Ecto.Changeset.change(run, status: status, output: output, diagnostic: diagnostic)
      )

      attempt!(run, status)
      ticket = Repo.update!(Ecto.Changeset.change(ticket, revision: ticket.revision + 1))
      # Reuse the durable refresh outbox, without ever dispatching Python through it.
      Instantflow.WorkflowRuntime.record(
        ticket,
        actor_for_audit(run),
        "calculation:" <> run.action_key,
        ticket.stage,
        nil,
        []
      )

      status
    end)
  end

  defp current?(run, ticket, version, sections, generation) do
    member = actor_for_audit(run)
    user = Repo.get!(Instantflow.Identity.User, member.user_id)
    actor = Access.load(member)
    review = Repo.get_by(Instantflow.Calculations.Review, script_id: run.script_id)
    script = Catalogue.script!(run.script_id)

    not Instantflow.WorkflowCatalog.Retirement.retired?(version.id) and
      member.active and user.active and review.enabled and review.verified and
      Access.role?(actor, ["python_execute"]) and Access.role?(actor, script.allowed_roles) and
      Enum.all?(
        referenced_sections(version, run.spec),
        &Policy.section?(actor, ticket, version, &1, :read)
      ) and
      run.generation == generation and run.review_generation == review.generation and
      ticket.stage == run.stage and ticket.stage_revision == run.stage_revision and
      revisions(run.spec, sections) == run.revisions and
      snapshot(run.spec, sections) == run.snapshot
  end

  defp result(_, _, _, false),
    do: {"stale", nil, "Resultado desatualizado ou permissão revogada."}

  defp result(request, {:ok, response}, script, true) do
    cond do
      not Runner.identity?(request, response) ->
        {"failed", nil, "Resposta do executor recusada."}

      response["status"] == "timed_out" ->
        {"timed_out", nil, "Tempo limite excedido. Revise o cálculo antes de tentar novamente."}

      response["status"] == "succeeded" and
          Contract.values?(script.output_schema, response["output"]) ->
        {"succeeded", response["output"], nil}

      true ->
        {"failed", nil, "O cálculo falhou ou retornou valores inválidos."}
    end
  end

  defp result(_, _, _, true),
    do: {"failed", nil, "Executor indisponível. Tente novamente mais tarde."}

  def control(actor, id, operation) when operation in ~w(retry cancel) do
    Tenant.transaction(actor, fn a ->
      Catalogue.permit!(a, "python_execute")
      original = Repo.get(Run, id) || Repo.rollback(:not_found)
      ticket = Repo.one!(from t in Ticket, where: t.id == ^original.ticket_id, lock: "FOR UPDATE")
      run = Repo.one!(from r in Run, where: r.id == ^id, lock: "FOR UPDATE")
      unless run.membership_id == a.id, do: Repo.rollback(:forbidden)

      if operation == "retry" do
        generation = switch!()
        sections = Repo.all(from s in Section, where: s.ticket_id == ^ticket.id)
        version = Repo.get!(Version, ticket.workflow_version_id)

        unless run.status in ~w(failed timed_out) and run.attempts < 3 and
                 current?(run, ticket, version, sections, generation),
               do: Repo.rollback(:calculation_required)
      else
        unless run.status in ~w(queued running failed timed_out), do: Repo.rollback(:forbidden)
      end

      if run.status == "running", do: attempt!(run, "cancelled")

      Repo.update!(
        Ecto.Changeset.change(run,
          status: if(operation == "retry", do: "queued", else: "cancelled"),
          fence: nil,
          lease_until: nil,
          diagnostic: nil
        )
      )

      ticket = Repo.update!(Ecto.Changeset.change(ticket, revision: ticket.revision + 1))

      Instantflow.WorkflowRuntime.record(
        ticket,
        a,
        "calculation:" <> operation,
        ticket.stage,
        nil,
        []
      )

      :ok
    end)
  end

  # Only a bounded status projection; source, snapshots and runner stdout never enter ticket views.
  def statuses(actor, ticket, version) do
    if Contract.calculations?(version.definition),
      do: calculation_statuses(actor, ticket, version),
      else: []
  end

  defp calculation_statuses(actor, ticket, version) do
    [[enabled, generation]] =
      Repo.query!("SELECT enabled, generation FROM calculation_switch WHERE id = 1").rows

    enabled = enabled and Application.get_env(:instantflow, :calculation_execution, false)

    Repo.all(
      from r in Run,
        join: review in Instantflow.Calculations.Review,
        on: review.script_id == r.script_id,
        where: r.ticket_id == ^ticket.id,
        order_by: [desc: r.id],
        limit: 20,
        select: {r, review.enabled, review.generation}
    )
    |> Enum.map(fn {run, script_enabled, script_generation} ->
      if run.status in ~w(queued running succeeded) and
           (not enabled or run.generation != generation or not script_enabled or
              run.review_generation != script_generation),
         do: %{
           run
           | status: "stale",
             diagnostic: "Execução desativada ou versão do cálculo alterada."
         },
         else: run
    end)
    |> Enum.filter(fn r ->
      Enum.all?(
        referenced_sections(version, r.spec),
        &Policy.section?(actor, ticket, version, &1, :read)
      )
    end)
    |> Enum.map(fn r ->
      %{
        id: r.id,
        status: r.status,
        attempts: r.attempts,
        diagnostic: r.diagnostic,
        controllable: r.membership_id == actor.id and Access.role?(actor, ["python_execute"])
      }
    end)
  end

  defp actor_for_audit(run), do: Repo.get!(Instantflow.Identity.Membership, run.membership_id)

  defp actor!(run) do
    member = actor_for_audit(run)
    Instantflow.Identity.scope(member.user_id, run.organization_id) || Repo.rollback(:forbidden)
  end

  defp authorize_inputs!(actor, ticket, version, script, spec) do
    Catalogue.permit!(actor, "python_execute")

    unless Access.role?(actor, script.allowed_roles) and
             Enum.all?(
               referenced_sections(version, spec),
               &Policy.section?(actor, ticket, version, &1, :read)
             ),
           do: Repo.rollback(:forbidden)
  end

  defp referenced_sections(version, spec),
    do:
      Contract.sections(version.definition, spec["inputs"]) ++
        Contract.sections(version.definition, spec["outputs"])

  defp revisions(spec, sections) do
    refs = Map.values(spec["inputs"])

    sections
    |> Enum.filter(fn s -> Enum.any?(refs, &String.starts_with?(&1, s.key <> ".")) end)
    |> Map.new(&{&1.key, &1.revision})
  end

  defp snapshot(spec, sections) do
    values = for s <- sections, {k, v} <- s.values, into: %{}, do: {s.key <> "." <> k, v}
    Map.new(spec["inputs"], fn {k, ref} -> {k, values[ref]} end)
  end

  defp apply_output!(run, output, sections) do
    Enum.each(
      Enum.group_by(run.spec["outputs"], fn {_, ref} -> hd(String.split(ref, ".")) end),
      fn {key, mappings} ->
        section = Enum.find(sections, &(&1.key == key))

        values =
          Enum.reduce(mappings, section.values, fn {k, ref}, acc ->
            Map.put(acc, List.last(String.split(ref, ".")), output[k])
          end)

        Repo.update!(
          Ecto.Changeset.change(section, values: values, revision: section.revision + 1)
        )
      end
    )
  end

  defp attempt!(run, result),
    do:
      Repo.insert!(
        %Attempt{
          organization_id: run.organization_id,
          run_id: run.id,
          fence: run.fence,
          number: run.attempts,
          result: result
        },
        on_conflict: :nothing
      )

  def purge_expired(organization_id) do
    cutoff = DateTime.add(DateTime.utc_now(), -7, :day)

    Tenant.raw(organization_id, fn ->
      Repo.update_all(
        from(r in Run,
          where:
            r.inserted_at < ^cutoff and r.status not in ["queued", "running"] and
              r.snapshot != ^%{}
        ),
        set: [snapshot: %{}, output: nil, diagnostic: nil, status: "stale"]
      )
    end)
  end

  def invalidate!(ticket, section_key \\ nil) do
    runs =
      Repo.all(
        from r in Run,
          where: r.ticket_id == ^ticket.id and r.status in ["queued", "running", "succeeded"]
      )

    Enum.each(runs, fn run ->
      affected =
        if section_key,
          do: Map.has_key?(run.revisions, section_key),
          else: run.status != "succeeded" and run.stage_revision != ticket.stage_revision

      if affected do
        if run.status == "running", do: attempt!(run, "stale")
        Repo.update!(Ecto.Changeset.change(run, status: "stale", fence: nil, lease_until: nil))
      end
    end)
  end

  def label("queued"), do: "Na fila"
  def label("running"), do: "Em execução"
  def label("succeeded"), do: "Concluído"
  def label("failed"), do: "Falhou"
  def label("timed_out"), do: "Tempo limite excedido"
  def label("cancelled"), do: "Cancelado"
  def label("stale"), do: "Resultado desatualizado"
end
