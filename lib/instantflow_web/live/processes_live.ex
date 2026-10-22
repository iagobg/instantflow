defmodule InstantflowWeb.ProcessesLive do
  use InstantflowWeb, :live_view
  alias Instantflow.WorkflowCatalog.Workspaces

  def mount(_, _, socket) do
    {:ok, socket |> assign(page_title: "Processos") |> load()}
  end

  def handle_info(_, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    processes = Workspaces.installed(socket.assigns.current_scope)

    participant_pages =
      Instantflow.WorkflowRuntime.Projections.participant_options(socket.assigns.current_scope)

    socket
    |> assign(empty?: processes == [] and participant_pages == [])
    |> stream(:processes, processes, reset: true)
    |> stream(:participant_pages, participant_pages, reset: true)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
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
      <p :if={@empty?} id="processes-empty" class="card">
        Nenhum processo disponível. Crie um modelo, revise os acessos e publique para começar.
      </p>
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
      <div id="participant-entry-pages" phx-update="stream" class="foundation-grid">
        <section :for={{id, page} <- @streams.participant_pages} id={id} class="card">
          <h2>{page.label}</h2>
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
