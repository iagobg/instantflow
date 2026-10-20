defmodule InstantflowWeb.RequestsLive do
  use InstantflowWeb, :live_view
  alias Instantflow.{WorkflowCatalog, WorkflowRuntime}

  def mount(_params, _session, socket) do
    versions = WorkflowCatalog.available(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(
       page_title: "Solicitações",
       has_workflows: versions != [],
       create_key: Ecto.UUID.generate(),
       form: to_form(%{}, as: :request),
       options: Enum.map(versions, &{&1.definition["name"], &1.workflow_id})
     )
     |> stream(:tickets, WorkflowRuntime.list(socket.assigns.current_scope))}
  end

  def handle_event("create", %{"request" => %{"workflow_id" => id}}, socket) do
    case Integer.parse(id) do
      {id, ""} ->
        case WorkflowRuntime.command(socket.assigns.current_scope, %{
               "operation" => "create",
               "key" => socket.assigns.create_key,
               "workflow_id" => id
             }) do
          {:ok, result} ->
            {:noreply, push_navigate(socket, to: ~p"/solicitacoes/#{result["ticket_id"]}")}

          {:error, error} ->
            {:noreply, put_flash(socket, :error, InstantflowWeb.RuntimeErrors.message(error))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Selecione um fluxo válido.")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="page-heading">
        <div>
          <p class="eyebrow">TRABALHO EM FLUXO</p><h1>Solicitações</h1><p>
            Seus pedidos e as análises do seu departamento. Até 100 solicitações recentes.
          </p>
        </div>
      </div>
      <section :if={@has_workflows} class="card create-request">
        <h2>Começar uma solicitação</h2><.form for={@form} id="new-request-form" phx-submit="create">
          <.input
            field={@form[:workflow_id]}
            type="select"
            label="Fluxo de trabalho"
            options={@options}
            required
          /><button id="new-request" class="btn primary" phx-disable-with="Criando…">Nova solicitação
          <.icon name="hero-arrow-right" /></button>
        </.form>
      </section>
      <section class="card requests-list">
        <h2>Acompanhamento</h2><div id="tickets" phx-update="stream">
          <p id="tickets-empty" class="empty-state">
            Nenhuma solicitação disponível. Comece pelo formulário acima.
          </p><.link
            :for={{id, ticket} <- @streams.tickets}
            id={id}
            navigate={~p"/solicitacoes/#{ticket.id}"}
            class="request-row"
          ><div>
            <strong>Solicitação #{ticket.id}</strong><small>{ticket.workflow_version.definition[
              "name"
            ]} · Versão {ticket.workflow_version.number}</small>
          </div><span class="badge">{stage_label(ticket)}</span><.icon name="hero-arrow-right" /></.link>
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
