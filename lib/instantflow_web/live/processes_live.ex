defmodule InstantflowWeb.ProcessesLive do
  use InstantflowWeb, :live_view
  import InstantflowWeb.PaginationControls
  alias Instantflow.WorkflowCatalog.Workspaces

  def mount(_, _, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Processos",
       discovery_filters: %{},
       entry_pages: %{"participant" => 1, "inbox" => 1},
       discovery_form: to_form(%{}, as: :discovery)
     )
     |> load()}
  end

  def handle_event("discovery-filter", %{"discovery" => params}, socket),
    do:
      {:noreply,
       socket
       |> assign(
         discovery_filters: Map.put(params, "page", "1"),
         discovery_form: to_form(params, as: :discovery)
       )
       |> load()}

  def handle_event("entry-page", %{"kind" => kind, "page" => page}, socket)
      when kind in ~w(participant inbox),
      do:
        {:noreply,
         socket |> assign(:entry_pages, Map.put(socket.assigns.entry_pages, kind, page)) |> load()}

  def handle_event("discovery-page", %{"page" => page}, socket),
    do:
      {:noreply,
       socket
       |> assign(:discovery_filters, Map.put(socket.assigns.discovery_filters, "page", page))
       |> load()}

  def handle_info(_, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    discovered = Workspaces.search(socket.assigns.current_scope, socket.assigns.discovery_filters)
    processes = discovered.rows

    inboxes =
      Instantflow.Delivery.Curated.discovery(socket.assigns.current_scope, %{
        "page" => socket.assigns.entry_pages["inbox"]
      })

    participant_pages =
      Instantflow.WorkflowRuntime.Projections.participant_discovery(
        socket.assigns.current_scope,
        %{"page" => socket.assigns.entry_pages["participant"]}
      )

    socket
    |> assign(:discovery, Map.delete(discovered, :rows))
    |> assign(
      entry_discovery: %{
        participant: Map.delete(participant_pages, :rows),
        inbox: Map.delete(inboxes, :rows)
      }
    )
    |> assign(
      empty?: discovered.total == 0 and participant_pages.total == 0 and inboxes.total == 0
    )
    |> stream(:inboxes, inboxes.rows, reset: true)
    |> stream(:processes, processes, reset: true)
    |> stream(:participant_pages, participant_pages.rows, reset: true)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} navigation={@workspace_navigation}>
      <div class="page-heading">
        <div>
          <p class="eyebrow">ESPAÇO DE TRABALHO</p><h1>Processos</h1><p>
            Os processos publicados pela sua organização.
          </p>
        </div>
        <.link
          :if={@current_scope.role == "admin"}
          id="create-process"
          navigate={~p"/o/#{@current_scope.organization.slug}/modelos"}
          class="btn primary"
        >Criar ou adaptar um processo</.link>
      </div>
      <.form
        for={@discovery_form}
        id="process-discovery-filters"
        phx-submit="discovery-filter"
        class="operations-form"
      >
        <.input field={@discovery_form[:query]} label="Buscar processo" maxlength="100" />
        <button id="process-discovery-filter" class="btn">Buscar</button>
      </.form>
      <.pagination
        id="process-discovery"
        event="discovery-page"
        info={@discovery}
        label="processo(s)"
      />
      <p :if={@empty?} id="processes-empty" class="card">
        Nenhum processo disponível. Crie um modelo, revise os acessos e publique para começar.
      </p>
      <.pagination
        :if={@entry_discovery.inbox.total > 0}
        id="inbox-discovery"
        event="entry-page"
        kind="inbox"
        info={@entry_discovery.inbox}
        label="caixa(s) de mensagens"
      />
      <div id="communication-entry-pages" phx-update="stream">
        <section :for={{id, inbox} <- @streams.inboxes} id={id} class="card">
          <.link
            id={"inbox-entry-#{inbox.id}"}
            navigate={~p"/o/#{@current_scope.organization.slug}/processos/#{inbox.id}/comunicacoes"}
          >{inbox.label}</.link>
        </section>
      </div>
      <div id="installed-processes" phx-update="stream" class="foundation-grid">
        <section :for={{id, version} <- @streams.processes} id={id} class="card">
          <h2>{version.definition["name"]}</h2><p>{version.definition["description"]}</p><p>
            {Enum.map_join(Workspaces.pages(version.definition), " · ", & &1["label"])}
          </p>
          <.link
            id={"open-process-#{version.workflow_id}"}
            navigate={~p"/o/#{@current_scope.organization.slug}/processos/#{version.workflow_id}"}
            class="btn primary"
          >Abrir processo</.link>
        </section>
      </div>
      <.pagination
        :if={@entry_discovery.participant.total > 0}
        id="participant-discovery"
        event="entry-page"
        kind="participant"
        info={@entry_discovery.participant}
        label="página(s) de participação"
      />
      <div id="participant-entry-pages" phx-update="stream" class="foundation-grid">
        <section :for={{id, page} <- @streams.participant_pages} id={id} class="card">
          <h2>{page.process_label} · {page.label}</h2>
          <.link
            id={"participant-entry-#{page.workflow_id}-#{page.key}"}
            navigate={
              ~p"/o/#{@current_scope.organization.slug}/processos/#{page.workflow_id}/participacao/#{page.key}"
            }
          >Abrir participação</.link>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
