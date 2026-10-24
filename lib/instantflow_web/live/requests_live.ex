defmodule InstantflowWeb.RequestsLive do
  use InstantflowWeb, :live_view
  import InstantflowWeb.PaginationControls
  alias Instantflow.{WorkflowCatalog, WorkflowRuntime}
  alias Instantflow.WorkflowCatalog.Views

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
       selected_view: "",
       view_options_page: 1,
       view_form: to_form(%{}, as: :view),
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

  def handle_event("view-options-page", %{"page" => page}, socket),
    do:
      {:noreply,
       socket
       |> assign(view_options_page: page, selected_view: "", view_form: to_form(%{}, as: :view))
       |> load()}

  def handle_event("configured-view", %{"view" => %{"key" => key}}, socket) do
    selected =
      Views.discovery(
        socket.assigns.current_scope,
        %{"page" => socket.assigns.view_options_page}
      ).rows
      |> Enum.find(&(&1.id == key))

    if selected && selected.type == "board" do
      {:noreply,
       push_navigate(socket,
         to:
           ~p"/o/#{socket.assigns.current_scope.organization.slug}/processos/#{selected.workflow_id}?#{%{view: selected.key}}"
       )}
    else
      {:noreply,
       socket
       |> assign(selected_view: key, view_form: to_form(%{"key" => key}, as: :view))
       |> load()}
    end
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
      when event in [:requests_changed, :reconcile, :permissions_changed, :workspaces_changed],
      do: {:noreply, load(socket)}

  defp load(socket) do
    versions =
      WorkflowCatalog.available(socket.assigns.current_scope)
      |> Enum.reject(&Instantflow.WorkflowCatalog.Workspaces.operational?(&1.definition))

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
    |> load_view()
  end

  defp load_view(socket) do
    discovery =
      Views.discovery(socket.assigns.current_scope, %{"page" => socket.assigns.view_options_page})

    options = discovery.rows
    selected = Enum.find(options, &(&1.id == socket.assigns.selected_view))

    result =
      if selected && selected.type != "board" do
        [id, key] = String.split(selected.id, ":", parts: 2)

        Views.search(
          socket.assigns.current_scope,
          String.to_integer(id),
          key,
          socket.assigns.filters
        )
      else
        %{rows: [], total: 0, columns: [], stages: []}
      end

    socket
    |> assign(
      view_discovery: Map.delete(discovery, :rows),
      view_options: Enum.map(options, &{&1.label, &1.id}),
      view_columns: result.columns,
      view_total: result.total,
      calendar?: Enum.any?(result.rows, &(&1.type == "calendar"))
    )
    |> stream(:configured_rows, result.rows, reset: true)
  end

  defp cell(row, key),
    do: Enum.find_value(row.cells, "—", fn c -> if c.key == key, do: display(c.value) end)

  defp display(value), do: InstantflowWeb.ProjectionDisplay.preview(value)

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} navigation={@workspace_navigation}>
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
        <p>
          Escolha um fluxo abaixo ou <.link
            id="all-creatable-processes"
            navigate={~p"/o/#{@current_scope.organization.slug}/processos"}
          >busque todos os processos disponíveis</.link>.
        </p>
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
      <.pagination
        id="global-view-browser"
        event="view-options-page"
        info={@view_discovery}
        label="visualização(ões)"
      />
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
      <section id="configured-views" class="card template-section">
        <h2>Visualizações do processo</h2><p>
          As visualizações respeitam suas permissões atuais. Quadros abrem no espaço do processo, com seleção de versão e paginação por etapa.
        </p>
        <.form for={@view_form} id="configured-view-form" phx-submit="configured-view">
          <.input
            field={@view_form[:key]}
            type="select"
            label="Visualização"
            options={@view_options}
            prompt="Selecione um processo e uma visualização"
          />
          <button id="apply-configured-view" class="btn">Abrir visualização</button>
        </.form>
        <p id="configured-view-count">
          {@view_total} resultado(s) autorizados · até 25 por página, conforme os filtros acima.
        </p>
        <p id="configured-preview-note" class="small-text">
          Textos longos mostram até 80 caracteres. Abra o registro para ver o conteúdo completo.
        </p>
        <div :if={@calendar?} id="configured-calendar" phx-update="stream" class="foundation-grid">
          <article :for={{id, row} <- @streams.configured_rows} id={id} class="card">
            <h3><time>{row.date || "Sem data"}</time></h3><span class="badge">{row.stage_label}</span>
            <p>
              <.link navigate={~p"/o/#{@current_scope.organization.slug}/solicitacoes/#{row.id}"}>Solicitação #{row.id}</.link>
            </p>
            <dl>
              <div :for={c <- row.cells}>
                <dt>{c.label}</dt><dd>{display(c.value)}</dd>
              </div>
            </dl>
          </article>
        </div>
        <div class="table-scroll">
          <table :if={!@calendar?} id="configured-table">
            <thead>
              <tr>
                <th>Solicitação</th><th :for={column <- @view_columns} scope="col">{column.label}</th>
              </tr>
            </thead><tbody id="configured-rows" phx-update="stream">
              <tr :for={{id, row} <- @streams.configured_rows} id={id}>
                <td>
                  <.link navigate={~p"/o/#{@current_scope.organization.slug}/solicitacoes/#{row.id}"}>#{row.id}</.link>
                </td><td :for={column <- @view_columns}>{cell(row, column.key)}</td>
              </tr>
            </tbody>
          </table>
        </div>
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
