defmodule InstantflowWeb.MessagesLive do
  use InstantflowWeb, :live_view
  alias Instantflow.Delivery.Curated

  def mount(_, _, socket), do: {:ok, assign(socket, page_title: "Mensagens compartilhadas")}

  def handle_params(params, _, socket) do
    id =
      case Integer.parse(params["workflow_id"]) do
        {n, ""} when n > 0 -> n
        _ -> -1
      end

    {:noreply, socket |> assign(workflow_id: id, params: params) |> load()}
  end

  def handle_info(_, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    data =
      Curated.inbox(
        socket.assigns.current_scope,
        socket.assigns.workflow_id,
        socket.assigns.params
      )

    socket |> assign(data: Map.drop(data, [:rows])) |> stream(:messages, data.rows, reset: true)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} navigation={@workspace_navigation}>
      <.link navigate={~p"/o/#{@current_scope.organization.slug}/processos"}>Processos</.link>
      <h1>Mensagens compartilhadas</h1>
      <p id="message-count">{@data.total} mensagem(ns) · Simulação de entrega</p>
      <div id="curated-inbox" phx-update="stream">
        <article :for={{id, message} <- @streams.messages} id={id} class="card">
          <h2>{message.label}</h2><p>{message.status}</p>
          <dl>
            <div :for={field <- message.content}>
              <dt>{field["label"]}</dt><dd>{value(field["value"])}</dd>
            </div>
          </dl>
        </article>
      </div>
      <nav id="message-pages">
        <.link
          :if={@data.page > 1}
          id="messages-previous"
          patch={
            ~p"/o/#{@current_scope.organization.slug}/processos/#{@workflow_id}/comunicacoes?page=#{@data.page - 1}"
          }
        >Anterior</.link>
        <span>{@data.page} / {@data.pages}</span>
        <.link
          :if={@data.page < @data.pages}
          id="messages-next"
          patch={
            ~p"/o/#{@current_scope.organization.slug}/processos/#{@workflow_id}/comunicacoes?page=#{@data.page + 1}"
          }
        >Próxima</.link>
      </nav>
    </Layouts.app>
    """
  end

  defp value(value) when is_binary(value), do: value
  defp value(value), do: Jason.encode!(value)
end
