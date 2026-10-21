defmodule InstantflowWeb.RequestsLive do
  use InstantflowWeb, :live_view
  alias Instantflow.{WorkflowCatalog, WorkflowRuntime}

  def mount(_params, _session, socket) do
    if connected?(socket),
      do:
        Phoenix.PubSub.subscribe(
          Instantflow.PubSub,
          WorkflowRuntime.list_topic(socket.assigns.current_scope)
        )

    {:ok,
     socket
     |> assign(
       page_title: "Solicitações",
       create_key: Ecto.UUID.generate(),
       filters: %{},
       filter_form: to_form(%{}, as: :filter),
       form: to_form(%{}, as: :request)
     )
     |> load()}
  end

  def handle_event("filter", %{"filter" => filters}, socket) do
    {:noreply,
     socket
     |> assign(filters: Map.put(filters, "page", "1"), filter_form: to_form(filters, as: :filter))
     |> load()}
  end

  def handle_event("page", %{"page" => page}, socket) do
    {:noreply,
     socket |> assign(:filters, Map.put(socket.assigns.filters, "page", page)) |> load()}
  end

  def handle_event(event, _, socket) when event in ["reconcile", "heartbeat"],
    do: {:noreply, load(socket)}

  def handle_event("create", %{"request" => %{"workflow_id" => id}}, socket) do
    case Integer.parse(id) do
      {id, ""} ->
        case WorkflowRuntime.command(socket.assigns.current_scope, %{
               "operation" => "create",
               "key" => socket.assigns.create_key,
               "workflow_id" => id
             }) do
          {:ok, result} ->
            {:noreply,
             push_navigate(socket,
               to:
                 ~p"/o/#{socket.assigns.current_scope.organization.slug}/solicitacoes/#{result["ticket_id"]}"
             )}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, InstantflowWeb.RuntimeErrors.message(error))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Selecione um fluxo válido.")}
    end
  end

  def handle_info(event, socket)
      when event in [:requests_changed, :reconcile, :permissions_changed],
      do: {:noreply, load(socket)}

  defp load(socket) do
    versions = WorkflowCatalog.available(socket.assigns.current_scope)
    result = WorkflowRuntime.search(socket.assigns.current_scope, socket.assigns.filters)

    labels = result.stage_labels

    socket
    |> assign(
      has_workflows: versions != [],
      options: Enum.map(versions, &{&1.definition["name"], &1.workflow_id}),
      result: Map.delete(result, :tickets),
      stage_options:
        Enum.map(Enum.sort(result.counts), fn {key, count} ->
          {"#{labels[key] || key} (#{count})", key}
        end)
    )
    |> stream(:tickets, result.tickets, reset: true)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="page-heading">
        <div>
          <p class="eyebrow">TRABALHO EM FLUXO</p><h1>Solicitações</h1><p>
            Seus pedidos e as análises autorizadas para seus departamentos.
          </p>
        </div>
      </div>
      <div id="requests-connection" phx-hook="Collaboration" phx-update="ignore"></div>
      <section :if={@has_workflows} class="card create-request">
        <h2>Começar uma solicitação</h2>
        <.form for={@form} id="new-request-form" phx-submit="create">
          <.input
            field={@form[:workflow_id]}
            type="select"
            label="Fluxo de trabalho"
            options={@options}
            required
          />
          <button
            id="new-request"
            class="btn primary"
            data-authoritative
            phx-disable-with="Criando…"
          >Nova solicitação <.icon name="hero-arrow-right" /></button>
        </.form>
      </section>
      <section class="card requests-list">
        <div class="list-heading">
          <h2>Acompanhamento</h2><span id="requests-count" class="badge">{@result.total} disponíveis</span>
        </div>
        <.form for={@filter_form} id="request-filters" phx-submit="filter" class="request-filters">
          <.input field={@filter_form[:query]} label="Buscar por número ou fluxo" maxlength="100" />
          <.input
            field={@filter_form[:stage]}
            type="select"
            label="Etapa"
            options={@stage_options}
            prompt="Todas as etapas"
          />
          <button class="btn" id="apply-filters">Filtrar</button>
        </.form>
        <p id="filtered-count">
          {@result.filtered} resultado(s) · Página {@result.page} de {@result.pages}
        </p>
        <p :if={@result.filtered == 0} id="tickets-empty" class="empty-state">
          Nenhuma solicitação disponível para estes filtros.
        </p>
        <div class="table-scroll">
          <table>
            <thead>
              <tr>
                <th scope="col">Solicitação</th><th scope="col">Fluxo</th><th scope="col">Etapa</th><th scope="col">
                  Abrir
                </th>
              </tr>
            </thead>
            <tbody id="tickets" phx-update="stream">
              <tr :for={{id, ticket} <- @streams.tickets} id={id}>
                <td><strong>#{ticket.id}</strong></td>
                <td>
                  {ticket.workflow_version.definition["name"]}<small>Versão {ticket.workflow_version.number}</small>
                </td>
                <td><span class="badge">{stage_label(ticket)}</span></td>
                <td>
                  <.link
                    navigate={~p"/o/#{@current_scope.organization.slug}/solicitacoes/#{ticket.id}"}
                    aria-label={"Abrir solicitação #{ticket.id}"}
                  ><.icon name="hero-arrow-right" /></.link>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <nav class="pagination" aria-label="Páginas de solicitações">
          <button
            :if={@result.page > 1}
            id="previous-page"
            class="btn"
            phx-click="page"
            phx-value-page={@result.page - 1}
          >Anterior</button>
          <button
            :if={@result.page < @result.pages}
            id="next-page"
            class="btn"
            phx-click="page"
            phx-value-page={@result.page + 1}
          >Próxima</button>
        </nav>
      </section>
    </Layouts.app>
    """
  end

  defp stage_label(ticket),
    do:
      Enum.find(ticket.workflow_version.definition["stages"], &(&1["key"] == ticket.stage))[
        "label"
      ]
end
