defmodule InstantflowWeb.FlowLive do
  use InstantflowWeb, :live_view
  import InstantflowWeb.WorkflowGraphComponents
  alias Instantflow.{Delivery, WorkflowRuntime}
  alias Instantflow.WorkflowCatalog.{Flows, Graph}

  def mount(_, _, socket) do
    if connected?(socket),
      do:
        Phoenix.PubSub.subscribe(
          Instantflow.PubSub,
          WorkflowRuntime.list_topic(socket.assigns.current_scope)
        )

    {:ok,
     socket
     |> assign(
       page_title: "Fluxo publicado",
       flow: nil,
       workflow_id: nil,
       ticket_id: nil,
       subscribed_ticket_id: nil,
       graph_focus: nil
     )
     |> stream(:graph_nodes, [])
     |> stream(:graph_edges, [])
     |> stream(:flow_stages, [])}
  end

  def handle_params(params, _, socket) do
    {:noreply,
     socket
     |> assign(
       workflow_id: integer(params["workflow_id"]),
       ticket_id: integer(params["id"]),
       invalid_ticket?: Map.has_key?(params, "id") and is_nil(integer(params["id"])),
       graph_focus: nil
     )
     |> load()}
  end

  def handle_event("focus-stage", %{"graph" => %{"stage" => stage}}, socket) do
    socket = socket |> assign(:graph_focus, stage) |> load()

    {:noreply,
     push_event(socket, "workflow-graph-focus", %{stage: socket.assigns.graph_focus || ""})}
  end

  def handle_info(message, socket)
      when message in [:reconcile, :permissions_changed, :workspaces_changed, :requests_changed],
      do: {:noreply, load(socket)}

  def handle_info({:ticket_changed, organization_id, id}, socket) do
    if organization_id == socket.assigns.current_scope.organization_id and
         id == socket.assigns.ticket_id, do: {:noreply, load(socket)}, else: {:noreply, socket}
  end

  defp load(socket) do
    result =
      if socket.assigns.invalid_ticket?,
        do: {:error, :not_found},
        else:
          Flows.get(
            socket.assigns.current_scope,
            socket.assigns.workflow_id,
            socket.assigns.ticket_id
          )

    case result do
      {:ok, flow} ->
        stages = flow.definition["stages"]
        edges = flow.definition["transitions"]
        focus = socket.assigns.graph_focus || flow.current_stage || ""
        focus = if Enum.any?(stages, &(&1["key"] == focus)), do: focus, else: ""
        graph = Graph.layout(flow.definition, focus)
        labels = Map.new(stages, &{&1["key"], &1["label"]})

        accessible =
          Enum.map(stages, fn stage ->
            %{
              id: stage["key"],
              label: stage["label"],
              initial?: stage["initial"],
              terminal?: stage["terminal"],
              current?: stage["key"] == flow.current_stage,
              outgoing:
                edges
                |> Enum.filter(&(&1["from"] == stage["key"]))
                |> Enum.map(&%{key: &1["key"], label: &1["label"], destination: labels[&1["to"]]})
            }
          end)

        socket
        |> subscription(flow.ticket_id)
        |> assign(
          flow: flow,
          page_title: flow.name <> " · Fluxo publicado",
          graph_width: graph.width,
          graph_height: graph.height,
          graph_focus: focus,
          graph_form: to_form(%{"stage" => focus}, as: :graph),
          stage_options: Enum.map(stages, &{&1["label"], &1["key"]}),
          graph_empty?: stages == []
        )
        |> stream(:graph_nodes, graph.nodes, reset: true)
        |> stream(:graph_edges, graph.edges, reset: true)
        |> stream(:flow_stages, accessible, reset: true)

      _ ->
        socket
        |> subscription(nil)
        |> assign(flow: nil, page_title: "Fluxo indisponível", graph_focus: nil)
        |> stream(:graph_nodes, [], reset: true)
        |> stream(:graph_edges, [], reset: true)
        |> stream(:flow_stages, [], reset: true)
    end
  end

  defp subscription(socket, id) do
    previous = socket.assigns.subscribed_ticket_id
    organization_id = socket.assigns.current_scope.organization_id

    if connected?(socket) and previous != id do
      if previous,
        do:
          Phoenix.PubSub.unsubscribe(
            Instantflow.PubSub,
            Delivery.topic(organization_id, previous)
          )

      if id, do: Phoenix.PubSub.subscribe(Instantflow.PubSub, Delivery.topic(organization_id, id))
    end

    assign(socket, :subscribed_ticket_id, id)
  end

  defp integer(value) when is_binary(value) and byte_size(value) <= 18 do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> id
      _ -> nil
    end
  end

  defp integer(_), do: nil

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} navigation={@workspace_navigation}>
      <div :if={is_nil(@flow)} id="flow-unavailable" class="card" role="status">
        <h1>Fluxo indisponível</h1>
        <p>Este processo ou registro não está disponível para seu perfil nesta organização.</p>
        <.link
          id="flow-unavailable-back"
          navigate={~p"/o/#{@current_scope.organization.slug}/processos"}
        >Voltar aos processos</.link>
      </div>
      <div :if={@flow} id="published-flow">
        <nav class="process-page-tabs" aria-label="Navegação do fluxo">
          <.link
            id="flow-back-process"
            class="btn"
            navigate={~p"/o/#{@current_scope.organization.slug}/processos/#{@flow.workflow_id}"}
          >Voltar aos casos</.link>
          <.link
            :if={@flow.ticket_id}
            id="flow-back-record"
            class="btn"
            navigate={
              ~p"/o/#{@current_scope.organization.slug}/processos/#{@flow.workflow_id}/registros/#{@flow.ticket_id}"
            }
          >Voltar ao registro #{@flow.ticket_id}</.link>
          <.link
            :if={@flow.can_author?}
            id="flow-builder-link"
            class="btn"
            navigate={~p"/o/#{@current_scope.organization.slug}/modelos"}
          >Abrir modelos de fluxo</.link>
        </nav>
        <div class="page-heading">
          <div>
            <p class="eyebrow">FLUXO PUBLICADO</p>
            <h1>{@flow.name}</h1>
            <p id="flow-version" data-version-id={@flow.version_id}>
              Versão {@flow.number} · Publicada em
              <time datetime={DateTime.to_iso8601(@flow.published_at)}>{Calendar.strftime(
                @flow.published_at,
                "%d/%m/%Y"
              )}</time>
            </p>
            <p :if={@flow.ticket_id} id="flow-pin-context">
              Regras fixadas no registro #{@flow.ticket_id}. Alterações no modelo não modificam este fluxo.
            </p>
            <p :if={!@flow.ticket_id} id="flow-current-context">
              Visão da publicação mais recente. Abra um registro para consultar sua versão e etapa atual.
            </p>
          </div>
        </div>
        <p :if={@flow.archived?} id="flow-archived" role="status">
          Versão histórica arquivada. O fluxo foi preservado para consulta.
        </p>
        <p id="flow-visibility-note">
          Os caminhos exibidos respeitam seu acesso. Caminhos com histórico restrito podem aparecer apenas no registro autorizado. As ações disponíveis são verificadas no próprio registro.
        </p>
        <p :if={@graph_empty?} id="flow-empty" role="status">
          Nenhuma etapa disponível para exibição.
        </p>
        <section
          :if={!@graph_empty?}
          class="card template-section"
          aria-labelledby="flow-diagram-heading"
        >
          <h2 id="flow-diagram-heading">Etapas e caminhos</h2>
          <p>
            Explore o diagrama com a rolagem ou escolha uma etapa. A lista abaixo apresenta os nomes completos e destinos.
          </p>
          <div class="graph-toolbar">
            <.form for={@graph_form} id="graph-focus-form" phx-change="focus-stage">
              <.input
                field={@graph_form[:stage]}
                type="select"
                label="Destacar conexões da etapa"
                options={@stage_options}
                prompt="Todas as etapas"
              />
            </.form>
            <div class="graph-legend" aria-label="Legenda das conexões">
              <span><i class="graph-swatch"></i>Avanço</span>
              <span><i class="graph-swatch secondary"></i>Correção e outros caminhos</span>
            </div>
          </div>
          <.workflow_graph
            graph_width={@graph_width}
            graph_height={@graph_height}
            streams={@streams}
            current_stage={@flow.current_stage}
          />
        </section>
        <section class="card template-section" aria-labelledby="flow-list-heading">
          <h2 id="flow-list-heading">Lista de etapas e conexões</h2>
          <ol id="flow-stages" class="flow-stage-list" phx-update="stream">
            <li
              :for={{id, stage} <- @streams.flow_stages}
              id={id}
              data-stage={stage.id}
              aria-current={if stage.current?, do: "step"}
            >
              <h3>{stage.label}</h3>
              <p :if={stage.initial? || stage.terminal? || stage.current?}>
                {if stage.initial?, do: "Etapa inicial. "}{if stage.terminal?, do: "Etapa final. "}{if stage.current?,
                  do: "Etapa atual do registro."}
              </p>
              <ul :if={stage.outgoing != []}>
                <li :for={edge <- stage.outgoing} data-transition={edge.key}>
                  {edge.label} → {edge.destination}
                </li>
              </ul>
              <p :if={stage.outgoing == []}>Sem conexões de saída visíveis nesta versão.</p>
            </li>
          </ol>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
