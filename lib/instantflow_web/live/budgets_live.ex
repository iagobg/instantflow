defmodule InstantflowWeb.BudgetsLive do
  use InstantflowWeb, :live_view
  alias Instantflow.{Finance, Identity}

  def mount(_, _, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        Instantflow.PubSub,
        Finance.topic(socket.assigns.current_scope.organization_id)
      )

      Process.send_after(self(), :reconcile, 30_000)
    end

    {:ok,
     socket
     |> assign(
       page_title: "Orçamentos",
       form: to_form(%{}, as: :allocation),
       account_form: to_form(%{}, as: :account),
       allocation_key: Ecto.UUID.generate()
     )
     |> load()}
  end

  def handle_event("create-account", %{"account" => p}, socket) do
    result =
      Finance.create_account(socket.assigns.current_scope, integer(p["department_id"]), p["name"])

    {:noreply, finish(socket, result)}
  end

  def handle_event("allocate", %{"allocation" => p}, socket) do
    result =
      Finance.allocate(
        socket.assigns.current_scope,
        integer(p["account_id"]),
        integer(p["amount"]),
        p["reason"],
        socket.assigns.allocation_key
      )

    {:noreply, finish(socket, result)}
  end

  def handle_event(event, _, socket) when event in ~w(reconcile heartbeat),
    do: {:noreply, load(socket)}

  def handle_info(:reconcile, socket) do
    Process.send_after(self(), :reconcile, 30_000)
    {:noreply, load(socket)}
  end

  def handle_info(event, socket) when event in [:budgets_changed, :permissions_changed],
    do: {:noreply, load(socket)}

  defp finish(socket, {:ok, _}),
    do:
      socket
      |> assign(allocation_key: Ecto.UUID.generate(), form: to_form(%{}, as: :allocation))
      |> put_flash(:info, "Orçamento atualizado.")
      |> load()

  defp finish(socket, {:error, error}),
    do: socket |> put_flash(:error, InstantflowWeb.RuntimeErrors.message(error)) |> load()

  defp operation_label(op),
    do:
      Map.get(
        %{
          "allocate" => "Alocação",
          "reserve" => "Reserva",
          "post" => "Gasto confirmado",
          "release" => "Liberação",
          "reverse" => "Estorno",
          "complete" => "Recebimento concluído"
        },
        op,
        op
      )

  defp integer(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp load(socket) do
    actor = socket.assigns.current_scope
    accounts = Finance.accounts(actor)

    entries =
      Enum.flat_map(accounts, &Finance.entries(actor, &1.id))
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.id, :desc)
      |> Enum.take(100)

    socket
    |> assign(
      account_options: Enum.map(accounts, &{&1.name, &1.id}),
      departments: Enum.map(Identity.departments(actor), &{&1.name, &1.id}),
      allocator?: Instantflow.Access.role?(actor, ["finance_allocator"]),
      account_count: length(accounts)
    )
    |> stream(:accounts, accounts, reset: true)
    |> stream(:entries, entries, reset: true)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="page-heading">
        <div>
          <p class="eyebrow">FINANCEIRO</p><h1>Orçamentos</h1><p>
            Valores em centavos (BRL). Disponível = alocado − reservado − gasto.
          </p>
        </div>
      </div>
      <div id="budgets-connection" phx-hook="Collaboration" phx-update="ignore"></div>
      <section :if={@current_scope.role == "admin"} class="card template-section">
        <h2>Criar conta local</h2>
        <.form for={@account_form} id="budget-account-form" phx-submit="create-account">
          <.input field={@account_form[:name]} label="Nome" required maxlength="120" />
          <.input
            field={@account_form[:department_id]}
            type="select"
            label="Departamento financeiro"
            options={@departments}
            required
          />
          <button id="create-budget-account" class="btn">Criar conta</button>
        </.form>
      </section>
      <section :if={@allocator?} class="card template-section">
        <h2>Alocar recursos</h2>
        <.form for={@form} id="budget-allocation-form" phx-submit="allocate">
          <.input
            field={@form[:account_id]}
            type="select"
            label="Orçamento"
            options={@account_options}
            required
          />
          <.input
            field={@form[:amount]}
            type="number"
            label="Valor em centavos"
            min="1"
            max="1000000000000"
            required
          />
          <.input field={@form[:reason]} label="Motivo auditável" required maxlength="2000" />
          <button id="allocate-budget" class="btn primary" phx-disable-with="Alocando…">Alocar</button>
        </.form>
      </section>
      <section class="card template-section">
        <h2>Contas autorizadas</h2><p id="budget-count">{@account_count} conta(s)</p>
        <div class="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Conta</th><th>Alocado</th><th>Reservado</th><th>Gasto</th><th>Disponível</th>
              </tr>
            </thead>
            <tbody id="budget-accounts" phx-update="stream">
              <tr :for={{id, account} <- @streams.accounts} id={id}>
                <td>{account.name}</td><td>{account.allocated}</td><td>{account.reserved}</td><td>
                  {account.spent}
                </td><td>{account.available}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
      <section class="card template-section">
        <h2>Movimentações auditadas</h2><p>Até 100 movimentações recentes das contas autorizadas.</p>
        <div id="budget-entries" phx-update="stream">
          <article :for={{id, entry} <- @streams.entries} id={id} class="note">
            <div>
              <strong>{operation_label(entry.operation)} · {entry.amount} centavos</strong><p>
                {entry.reason}
              </p><small>Conta #{entry.account_id} · Solicitação {entry.ticket_id ||
                "—"} · Autor #{entry.actor_id} · {entry.inserted_at}</small>
            </div>
          </article>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
