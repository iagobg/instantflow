defmodule Instantflow.Finance do
  @moduledoc "Integer-cent accounting. Runtime locks ticket, then shared account, then hold; all effects commit with the workflow."
  import Ecto.Query
  alias Instantflow.{Access, Repo, Tenant}
  alias Instantflow.Finance.{Account, Entry, Hold}

  def install(actor, template, departments, account_id)
      when template in ~w(requisition field_trip) do
    definition =
      File.read!(Application.app_dir(:instantflow, "priv/workflows/#{template}.json"))
      |> Jason.decode!()

    Instantflow.WorkflowCatalog.publish(actor, definition, %{
      "roles" => %{
        "requester" => ["teacher"],
        "head" => ["head"],
        "finance" => ["finance"],
        "operations" => ["operations"],
        "safety" => ["dean"],
        "reverser" => ["finance_reverser"]
      },
      "departments" => departments,
      "budgets" => %{"shared_budget" => account_id}
    })
  end

  def create_account(actor, department_id, name) do
    Tenant.transaction(actor, fn a ->
      unless a.role == "admin" and is_binary(name) and String.length(String.trim(name)) in 1..120 and
               Repo.get_by(Instantflow.Identity.Department,
                 id: department_id,
                 organization_id: a.organization_id
               ),
             do: Repo.rollback(:forbidden)

      %Account{
        organization_id: a.organization_id,
        department_id: department_id,
        name: String.trim(name),
        allocated: 0,
        reserved: 0,
        spent: 0
      }
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.unique_constraint([:organization_id, :department_id, :name])
      |> Repo.insert()
      |> case do
        {:ok, account} -> account
        {:error, _} -> Repo.rollback(:account_exists)
      end
    end)
  end

  def allocate(actor, account_id, amount, reason, key) do
    result =
      Tenant.transaction(actor, fn a ->
        account = account!(account_id)
        permit!(a, account, "finance_allocator")

        unless positive?(amount) and reason?(reason) and is_binary(key) and
                 byte_size(key) in 1..120,
               do: Repo.rollback(:invalid_values)

        key = "allocation:#{a.user_id}:" <> key
        existing = Repo.get_by(Entry, organization_id: a.organization_id, key: key)

        if existing do
          unless existing.actor_id == a.user_id and existing.account_id == account.id and
                   existing.operation == "allocate" and existing.amount == amount and
                   existing.reason == reason,
                 do: Repo.rollback(:idempotency_mismatch)

          account
        else
          updated = change!(account, allocated: account.allocated + amount)
          entry!(a, account, nil, "allocate", amount, reason, key)
          updated
        end
      end)

    if match?({:ok, _}, result), do: broadcast(actor.organization_id)
    result
  end

  def binding_options(actor) do
    Tenant.read(
      actor,
      fn a ->
        unless a.role == "admin", do: Repo.rollback(:forbidden)
        Repo.all(from b in Account, order_by: b.name, select: {b.name, b.id})
      end,
      []
    )
  end

  def accounts(actor) do
    Tenant.read(
      actor,
      fn a ->
        Repo.all(from b in Account, order_by: b.id)
        |> Enum.filter(&view?(a, &1))
        |> Enum.map(&Map.put(&1, :available, &1.allocated - &1.reserved - &1.spent))
      end,
      []
    )
  end

  def entries(actor, account_id) do
    Tenant.read(
      actor,
      fn a ->
        account = Repo.get(Account, account_id)
        unless account && view?(a, account), do: Repo.rollback(:forbidden)

        Repo.all(
          from e in Entry, where: e.account_id == ^account.id, order_by: [desc: e.id], limit: 100
        )
      end,
      []
    )
  end

  def topic(id), do: "organization:#{id}:budgets"
  def broadcast(id), do: Phoenix.PubSub.broadcast(Instantflow.PubSub, topic(id), :budgets_changed)

  def validate_values!(version, sections, section, new_values) do
    values = Map.new(sections, &{&1.key, &1.values}) |> Map.put(section.key, new_values)

    for edge <- version.definition["transitions"],
        spec = edge["finance"],
        spec && spec["operation"] == "complete" do
      [received_section, received_key] = String.split(spec["received_field"], ".")

      if received_section == section.key do
        received = new_values[received_key]
        quantity = get_in(values, String.split(spec["quantity_field"], "."))

        unless is_nil(received) or
                 (is_integer(received) and received >= 0 and is_integer(quantity) and
                    received <= quantity),
               do: Repo.rollback(:invalid_delivery)
      end
    end
  end

  def effect!(_actor, _ticket, _version, nil, _values, _reason), do: :ok

  def effect!(actor, ticket, version, spec, values, reason) do
    account = account!(version.bindings["budgets"][spec["account_binding"]])
    hold = Repo.get_by(Hold, ticket_id: ticket.id)
    operation = spec["operation"]
    amount = values[spec["amount_field"]]

    if operation in ["reserve", "post"] and not positive?(amount),
      do: Repo.rollback(:invalid_amount)

    case operation do
      "reserve" ->
        permit!(actor, account, "finance")
        if actor.user_id == ticket.requester_id, do: Repo.rollback(:forbidden)

        if hold && hold.status not in ["released", "reversed"],
          do: Repo.rollback(:invalid_finance_state)

        unless account.allocated - account.reserved - account.spent >= amount,
          do: Repo.rollback(:insufficient_budget)

        change!(account, reserved: account.reserved + amount)
        attrs = [account_id: account.id, amount: amount, status: "reserved"]

        if hold,
          do: change!(hold, attrs),
          else:
            Repo.insert!(
              struct!(Hold, [
                {:organization_id, actor.organization_id},
                {:ticket_id, ticket.id} | attrs
              ])
            )

      "post" ->
        require_hold!(hold, account, "reserved")
        unless amount == hold.amount, do: Repo.rollback(:renew_finance_review)

        change!(account,
          reserved: account.reserved - hold.amount,
          spent: account.spent + hold.amount
        )

        change!(hold, status: "posted")

      "release" ->
        if hold && hold.status == "posted", do: Repo.rollback(:explicit_reversal_required)

        if hold && hold.status == "reserved" do
          require_hold!(hold, account, "reserved")
          change!(account, reserved: account.reserved - hold.amount)
          change!(hold, status: "released")
        end

      "reverse" ->
        permit!(actor, account, "finance_reverser")
        if actor.user_id == ticket.requester_id, do: Repo.rollback(:forbidden)
        unless reason?(reason), do: Repo.rollback(:reason_required)
        require_hold!(hold, account, "posted")
        change!(account, spent: account.spent - hold.amount)
        change!(hold, status: "reversed")

      "complete" ->
        require_hold!(hold, account, "posted")
        quantity = values[spec["quantity_field"]]
        received = values[spec["received_field"]]

        unless positive?(quantity) and is_integer(received) and received == quantity,
          do: Repo.rollback(:incomplete_delivery)
    end

    entry!(
      actor,
      account,
      ticket.id,
      operation,
      amount || (hold && hold.amount) || 0,
      reason || "Transição autorizada",
      "ticket:#{ticket.id}:#{ticket.revision + 1}"
    )
  end

  defp require_hold!(hold, account, status) do
    unless hold && hold.account_id == account.id && hold.status == status,
      do: Repo.rollback(:invalid_finance_state)
  end

  defp account!(nil), do: Repo.rollback(:invalid_budget)

  defp account!(id) do
    Repo.one(from b in Account, where: b.id == ^id, lock: "FOR UPDATE") ||
      Repo.rollback(:invalid_budget)
  end

  defp permit!(actor, account, role) do
    unless actor.role != "parent" and
             Enum.any?(
               Access.profiles(actor),
               &(&1.role == role and &1.department_id == account.department_id)
             ),
           do: Repo.rollback(:forbidden)
  end

  defp view?(actor, account),
    do:
      actor.role != "parent" and
        Enum.any?(
          Access.profiles(actor),
          &(&1.role in ~w(finance finance_allocator finance_reverser head) and
              &1.department_id == account.department_id)
        )

  defp positive?(n), do: is_integer(n) and n > 0 and n <= 1_000_000_000_000
  defp reason?(s), do: is_binary(s) and String.length(String.trim(s)) in 1..2000
  defp change!(row, attrs), do: row |> Ecto.Changeset.change(attrs) |> Repo.update!()

  defp entry!(a, account, ticket_id, op, amount, reason, key) do
    Repo.insert!(%Entry{
      organization_id: a.organization_id,
      account_id: account.id,
      ticket_id: ticket_id,
      actor_id: a.user_id,
      operation: op,
      amount: amount,
      reason: reason,
      key: key,
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end
end
