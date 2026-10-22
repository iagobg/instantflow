defmodule Instantflow.Operations do
  @moduledoc "Tenant-local catalog, resource visits, immutable line snapshots and destination batches. All writes are audited idempotent commands."
  import Ecto.Query
  alias Instantflow.{Repo, Tenant, WorkflowRuntime}
  alias Instantflow.WorkflowCatalog.Workspaces
  alias Instantflow.Operations.{Product, Resource, Session, Batch, Line, Receipt, DayClose}

  @operations ~w(save_product add_resource open_session submit_batch handoff cancel_batch print_ticket settle close_day)

  def command(actor, %{"operation" => operation, "key" => key} = command)
      when operation in @operations and is_binary(key) and byte_size(key) in 1..120 do
    result =
      Tenant.transaction(actor, fn scope ->
        version = workspace_version!(command["workflow_id"])
        action = if operation in ~w(save_product add_resource), do: "configure", else: "operate"
        permit!(scope, version, action)
        workflow_id = version.workflow_id
        # Serialize resource occupancy, daily close and all related writes within this tenant.
        # Existing tenant authorization locks are acquired first; no background worker takes this gate.
        Repo.query!(
          "SELECT pg_advisory_xact_lock(hashtextextended('operations:' || $1::text, 0))",
          [to_string(scope.organization_id)]
        )

        digest = :crypto.hash(:sha256, :erlang.term_to_binary(command, [:deterministic]))

        receipt =
          Repo.get_by(Receipt, actor_id: scope.user_id, workflow_id: workflow_id, key: key)

        if receipt do
          unless receipt.digest == digest, do: Repo.rollback(:idempotency_mismatch)
          receipt.result
        else
          value = execute(scope, workflow_id, operation, command)

          Repo.insert!(%Receipt{
            organization_id: scope.organization_id,
            workflow_id: workflow_id,
            actor_id: scope.user_id,
            key: key,
            operation: operation,
            digest: digest,
            result: value,
            reason: command["reason"],
            inserted_at: now()
          })

          value
        end
      end)

    if match?({:ok, _}, result),
      do: Phoenix.PubSub.broadcast(Instantflow.PubSub, topic(actor), :operations_changed)

    result
  end

  def command(_, _), do: {:error, :invalid_values}

  def topic(scope), do: "organization:#{scope.organization_id}:operations"

  def today do
    %{rows: [[date]]} = Repo.query!("SELECT (now() AT TIME ZONE 'America/Sao_Paulo')::date")
    date
  end

  def workspace(actor, date, workflow_id \\ nil) do
    Tenant.read(actor, fn scope ->
      version = workspace_version!(workflow_id)
      permit!(scope, version, "view")
      workflow_id = version.workflow_id

      %{
        version: version,
        labels: Workspaces.labels(version.definition),
        products:
          Repo.all(
            from p in Product,
              where: p.workflow_id == ^workflow_id,
              order_by: [p.category, p.name]
          ),
        resources:
          Repo.all(from r in Resource, where: r.workflow_id == ^workflow_id, order_by: r.name),
        sessions:
          Repo.all(
            from s in Session,
              where: s.workflow_id == ^workflow_id and s.status == "open",
              order_by: s.id
          ),
        report: report!(date, workflow_id)
      }
    end)
  end

  def visit(actor, id, workflow_id \\ nil) do
    Tenant.read(actor, fn scope ->
      session =
        if is_nil(workflow_id), do: Repo.get(Session, id), else: find!(Session, id, workflow_id)

      unless session, do: Repo.rollback(:not_found)
      permit!(scope, workspace_version!(session.workflow_id), "view")
      batches = Repo.all(from b in Batch, where: b.session_id == ^session.id, order_by: b.id)
      ids = Enum.map(batches, & &1.id)
      lines = Repo.all(from l in Line, where: l.batch_id in ^ids, order_by: l.id)

      %{
        session: session,
        batches:
          Enum.map(
            batches,
            &Map.put(&1, :lines, Enum.filter(lines, fn l -> l.batch_id == &1.id end))
          ),
        total: total!(session.id)
      }
    end)
  end

  # Runtime transitions cannot bypass checkout, including forged LiveView commands.
  def validate_transition!(ticket, version, transition) do
    terminal? =
      Enum.any?(version.definition["stages"], &(&1["key"] == transition["to"] and &1["terminal"]))

    has_session? = Repo.exists?(from s in Session, where: s.ticket_id == ^ticket.id)

    if terminal? and (Workspaces.operational?(version.definition) or has_session?) do
      unless Repo.exists?(
               from s in Session, where: s.ticket_id == ^ticket.id and s.status == "settled"
             ),
             do: Repo.rollback(:checkout_required)
    end
  end

  def money(cents) when is_integer(cents) do
    "R$ " <>
      Integer.to_string(div(cents, 100)) <>
      "," <> String.pad_leading(Integer.to_string(rem(cents, 100)), 2, "0")
  end

  def parse_money(text) when is_binary(text) do
    case Regex.run(~r/\A(0|[1-9][0-9]{0,6})(?:[,.]([0-9]{1,2}))?\z/, String.trim(text)) do
      [_, whole] ->
        {:ok, String.to_integer(whole) * 100}

      [_, whole, fraction] ->
        {:ok,
         String.to_integer(whole) * 100 + String.to_integer(String.pad_trailing(fraction, 2, "0"))}

      _ ->
        :error
    end
  end

  def parse_money(_), do: :error

  defp execute(a, workflow_id, "save_product", c) do
    attrs = %{
      name: text!(c["name"], 120),
      category: text!(c["category"], 80),
      destination: text!(c["destination"], 80),
      price: integer!(c["price"], 0, 100_000_000),
      active: c["active"] != false
    }

    product =
      if c["id"],
        do: find!(Product, c["id"], workflow_id),
        else: %Product{organization_id: a.organization_id, workflow_id: workflow_id}

    if product.id && product.revision != c["revision"], do: Repo.rollback(:conflict)

    if Repo.exists?(
         from p in Product,
           where:
             p.workflow_id == ^workflow_id and p.name == ^attrs.name and
               p.id != ^(product.id || 0)
       ),
       do: Repo.rollback(:duplicate_name)

    product =
      product
      |> Ecto.Changeset.change(Map.put(attrs, :revision, (product.revision || 0) + 1))
      |> Repo.insert_or_update!()

    %{"id" => product.id}
  end

  defp execute(a, workflow_id, "add_resource", c) do
    name = text!(c["name"], 80)

    if Repo.exists?(from r in Resource, where: r.workflow_id == ^workflow_id and r.name == ^name),
      do: Repo.rollback(:duplicate_name)

    resource =
      Repo.insert!(%Resource{
        organization_id: a.organization_id,
        workflow_id: workflow_id,
        name: name
      })

    %{"id" => resource.id}
  end

  defp execute(a, workflow_id, "open_session", c) do
    resource = find!(Resource, c["resource_id"], workflow_id)
    waiter = text!(c["waiter"], 120)
    date = date!(c["business_date"])
    open_day!(date, workflow_id)

    if Repo.exists?(
         from s in Session, where: s.resource_id == ^resource.id and s.status == "open"
       ),
       do: Repo.rollback(:occupied)

    version = workspace_version!(workflow_id)

    result =
      unwrap!(
        WorkflowRuntime.command(
          a,
          %{
            "operation" => "create",
            "key" => "service:" <> c["key"],
            "workflow_id" => version.workflow_id
          },
          :operations
        )
      )

    session =
      Repo.insert!(%Session{
        organization_id: a.organization_id,
        workflow_id: workflow_id,
        resource_id: resource.id,
        resource_name: resource.name,
        waiter: waiter,
        business_date: date,
        ticket_id: result["ticket_id"],
        opened_at: now()
      })

    %{"id" => session.id}
  end

  defp execute(a, workflow_id, "submit_batch", c) do
    session = open_session!(c["session_id"], workflow_id)
    lines = c["lines"]
    unless is_list(lines) and length(lines) in 1..100, do: Repo.rollback(:invalid_values)
    waiter = text!(c["waiter"] || session.waiter, 120)

    items =
      Enum.map(lines, fn line ->
        unless is_map(line), do: Repo.rollback(:invalid_values)
        product = find!(Product, line["product_id"], workflow_id)
        unless product.active, do: Repo.rollback(:inactive_product)
        unless product.revision == line["product_revision"], do: Repo.rollback(:catalog_changed)

        %{
          product: product,
          quantity: integer!(line["quantity"], 1, 999),
          notes: notes!(line["notes"] || "")
        }
      end)

    ids =
      items
      |> Enum.group_by(& &1.product.destination)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {destination, items} ->
        batch =
          Repo.insert!(%Batch{
            organization_id: a.organization_id,
            workflow_id: workflow_id,
            session_id: session.id,
            destination: destination,
            waiter: waiter,
            inserted_at: now()
          })

        for item <- items do
          Repo.insert!(%Line{
            organization_id: a.organization_id,
            workflow_id: workflow_id,
            batch_id: batch.id,
            product_id: item.product.id,
            name: item.product.name,
            unit_price: item.product.price,
            quantity: item.quantity,
            notes: item.notes
          })
        end

        batch.id
      end)

    %{"ids" => ids}
  end

  defp execute(_a, workflow_id, "handoff", c) do
    batch = find!(Batch, c["batch_id"], workflow_id)
    open_session!(batch.session_id, workflow_id)
    unless batch.status == "pending", do: Repo.rollback(:invalid_state)
    change!(batch, status: "handed")
    %{"id" => batch.id}
  end

  defp execute(a, workflow_id, "cancel_batch", c) do
    batch = find!(Batch, c["batch_id"], workflow_id)
    open_session!(batch.session_id, workflow_id)
    reason = text!(c["reason"], 500)

    unless batch.kind == "order" and batch.status != "cancelled",
      do: Repo.rollback(:invalid_state)

    change!(batch, status: "cancelled")

    cancellation =
      Repo.insert!(%Batch{
        organization_id: a.organization_id,
        workflow_id: workflow_id,
        session_id: batch.session_id,
        destination: batch.destination,
        waiter: batch.waiter,
        source_id: batch.id,
        kind: "cancellation",
        reason: reason,
        inserted_at: now()
      })

    for line <- Repo.all(from l in Line, where: l.batch_id == ^batch.id) do
      Repo.insert!(%Line{
        organization_id: a.organization_id,
        workflow_id: workflow_id,
        batch_id: cancellation.id,
        product_id: line.product_id,
        name: line.name,
        quantity: line.quantity,
        unit_price: line.unit_price,
        notes: line.notes
      })
    end

    %{"id" => cancellation.id}
  end

  defp execute(_a, workflow_id, "print_ticket", c) do
    batch = find!(Batch, c["batch_id"], workflow_id)
    unless batch.status != "cancelled", do: Repo.rollback(:invalid_state)
    change!(batch, print_count: batch.print_count + 1)
    # A request to open a print dialog is not evidence of physical printing or handoff.
    %{"id" => batch.id, "copy" => batch.print_count + 1}
  end

  defp execute(a, workflow_id, "settle", c) do
    session = open_session!(c["session_id"], workflow_id)
    unless c["payment_method"] in ~w(cash card pix), do: Repo.rollback(:invalid_values)

    if Repo.exists?(
         from b in Batch, where: b.session_id == ^session.id and b.status == "pending"
       ),
       do: Repo.rollback(:pending_handoff)

    total = total!(session.id)
    unless c["expected_total"] == total, do: Repo.rollback(:conflict)

    change!(session,
      status: "settled",
      total: total,
      payment_method: c["payment_method"],
      settled_at: now()
    )

    data = unwrap!(WorkflowRuntime.get(a, session.ticket_id))

    unwrap!(
      WorkflowRuntime.command(a, %{
        "operation" => "transition",
        "key" => "settle:" <> c["key"],
        "ticket_id" => session.ticket_id,
        "transition" =>
          Workspaces.close_transition(
            Repo.get!(Instantflow.WorkflowCatalog.Version, data.ticket.workflow_version_id).definition
          ),
        "expected_revision" => data.ticket.revision,
        "section_revisions" => Map.new(data.sections, &{&1.key, &1.revision})
      })
    )

    %{"id" => session.id, "total" => total}
  end

  defp execute(a, workflow_id, "close_day", c) do
    date = date!(c["business_date"])
    open_day!(date, workflow_id)
    summary = report!(date, workflow_id)

    if Repo.exists?(
         from s in Session,
           where:
             s.workflow_id == ^workflow_id and s.status == "open" and s.business_date <= ^date
       ),
       do: Repo.rollback(:open_sessions)

    close =
      Repo.insert!(%DayClose{
        organization_id: a.organization_id,
        workflow_id: workflow_id,
        business_date: date,
        actor_id: a.user_id,
        summary: Map.drop(summary, [:closed]) |> stringify(),
        inserted_at: now()
      })

    %{"id" => close.id}
  end

  defp report!(date, workflow_id) do
    date = date!(date)

    sessions =
      Repo.all(
        from s in Session, where: s.workflow_id == ^workflow_id and s.business_date == ^date
      )

    settled = Enum.filter(sessions, &(&1.status == "settled"))
    open = Enum.filter(sessions, &(&1.status == "open"))
    session_ids = Enum.map(sessions, & &1.id)

    lines =
      Repo.all(
        from l in Line,
          join: b in Batch,
          on: b.id == l.batch_id,
          where: b.session_id in ^session_ids and b.kind == "order" and b.status != "cancelled",
          select: l
      )

    consumption =
      lines
      |> Enum.group_by(& &1.product_id)
      |> Enum.map(fn {id, lines} ->
        %{
          product_id: id,
          name: List.last(lines).name,
          quantity: Enum.sum(Enum.map(lines, & &1.quantity))
        }
      end)
      |> Enum.sort_by(& &1.name)

    %{
      date: date,
      sales: Enum.sum(Enum.map(settled, & &1.total)),
      settled_count: length(settled),
      open_count: length(open),
      open_total: Enum.sum(Enum.map(open, &total!(&1.id))),
      payments:
        Map.new(~w(cash card pix), fn method ->
          {method,
           settled
           |> Enum.filter(&(&1.payment_method == method))
           |> Enum.map(& &1.total)
           |> Enum.sum()}
        end),
      cancellations:
        Repo.one(
          from l in Line,
            join: b in Batch,
            on: b.id == l.batch_id,
            where: b.session_id in ^session_ids and b.kind == "order" and b.status == "cancelled",
            select: fragment("COALESCE(SUM(? * ?), 0)::bigint", l.quantity, l.unit_price)
        ),
      consumption: consumption,
      closed: Repo.get_by(DayClose, workflow_id: workflow_id, business_date: date)
    }
  end

  defp total!(session_id) do
    Repo.one(
      from l in Line,
        join: b in Batch,
        on: b.id == l.batch_id,
        where: b.session_id == ^session_id and b.kind == "order" and b.status != "cancelled",
        select: fragment("COALESCE(SUM(? * ?), 0)::bigint", l.quantity, l.unit_price)
    )
  end

  def default_workflow(actor) do
    Tenant.read(actor, fn scope ->
      case Enum.filter(
             Workspaces.latest(),
             &(operational_version?(&1) and Workspaces.allowed?(scope, &1, "view"))
           ) do
        [version] -> version.workflow_id
        _ -> nil
      end
    end)
  end

  def workflow_for_visit(actor, id) when is_integer(id) do
    Tenant.read(actor, fn scope ->
      session = Repo.get(Session, id)
      if session, do: permit!(scope, workspace_version!(session.workflow_id), "view")
      session && session.workflow_id
    end)
  end

  def workflow_for_visit(_, _), do: nil

  defp workspace_version!(nil) do
    case Enum.filter(Workspaces.latest(), &operational_version?(&1)) do
      [version] -> version
      _ -> Repo.rollback(:workspace_required)
    end
  end

  defp workspace_version!(workflow_id) when is_integer(workflow_id) do
    version =
      Repo.one(
        from v in Instantflow.WorkflowCatalog.Version,
          where: v.workflow_id == ^workflow_id,
          order_by: [desc: v.number],
          limit: 1
      )

    unless version && operational_version?(version),
      do: Repo.rollback(:not_found)

    version
  end

  defp workspace_version!(_), do: Repo.rollback(:not_found)

  defp operational_version?(version) do
    Workspaces.operational?(version.definition) or
      Repo.exists?(from s in Session, where: s.workflow_id == ^version.workflow_id) or
      Repo.exists?(from p in Product, where: p.workflow_id == ^version.workflow_id) or
      Repo.exists?(from r in Resource, where: r.workflow_id == ^version.workflow_id)
  end

  defp open_session!(id, workflow_id) do
    session = find!(Session, id, workflow_id)
    unless session.status == "open", do: Repo.rollback(:invalid_state)
    open_day!(session.business_date, workflow_id)
    session
  end

  defp open_day!(date, workflow_id) do
    if Repo.exists?(
         from d in DayClose, where: d.workflow_id == ^workflow_id and d.business_date >= ^date
       ),
       do: Repo.rollback(:day_closed)

    if Date.compare(date, today()) == :gt, do: Repo.rollback(:invalid_date)
  end

  defp permit!(scope, version, action) do
    unless Workspaces.allowed?(scope, version, action), do: Repo.rollback(:forbidden)
  end

  defp find!(module, id, workflow_id) when is_integer(id),
    do:
      Repo.one(from row in module, where: row.id == ^id and row.workflow_id == ^workflow_id) ||
        Repo.rollback(:not_found)

  defp find!(_, _, _), do: Repo.rollback(:not_found)

  defp text!(text, max) when is_binary(text) do
    value = String.trim(text)
    unless String.length(value) in 1..max, do: Repo.rollback(:invalid_values)
    value
  end

  defp text!(_, _), do: Repo.rollback(:invalid_values)

  defp notes!(text) when is_binary(text) and byte_size(text) <= 1200 do
    unless String.length(text) <= 300, do: Repo.rollback(:invalid_values)
    String.trim(text)
  end

  defp notes!(_), do: Repo.rollback(:invalid_values)
  defp integer!(n, min, max) when is_integer(n) and n >= min and n <= max, do: n
  defp integer!(_, _, _), do: Repo.rollback(:invalid_values)
  defp date!(%Date{} = date), do: date

  defp date!(text) when is_binary(text) do
    case Date.from_iso8601(text) do
      {:ok, date} -> date
      _ -> Repo.rollback(:invalid_date)
    end
  end

  defp date!(_), do: Repo.rollback(:invalid_date)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp change!(row, attrs), do: row |> Ecto.Changeset.change(attrs) |> Repo.update!()
  defp unwrap!({:ok, result}), do: result
  defp unwrap!({:error, error}), do: Repo.rollback(error)
  defp stringify(value), do: value |> Jason.encode!() |> Jason.decode!()
end
