defmodule InstantflowWeb.IncidentsLive do
  use InstantflowWeb, :live_view
  alias Instantflow.{Incidents, WorkflowCatalog, WorkflowRuntime}

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
       page_title: "Ocorrências",
       filters: %{},
       form: to_form(%{}, as: :filter),
       create_key: Ecto.UUID.generate()
     )
     |> load()}
  end

  def handle_event("filter", %{"filter" => p}, socket),
    do: {:noreply, socket |> assign(filters: p, form: to_form(p, as: :filter)) |> load()}

  def handle_event("create", %{"id" => id}, socket) do
    result =
      case Integer.parse(id) do
        {id, ""} ->
          WorkflowRuntime.command(socket.assigns.current_scope, %{
            "operation" => "create",
            "workflow_id" => id,
            "key" => socket.assigns.create_key
          })

        _ ->
          {:error, :invalid_command}
      end

    case result do
      {:ok, result} ->
        {:noreply,
         push_navigate(socket,
           to:
             ~p"/o/#{socket.assigns.current_scope.organization.slug}/solicitacoes/#{result["ticket_id"]}"
         )}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, InstantflowWeb.RuntimeErrors.message(error))}
    end
  end

  def handle_event(event, _, socket) when event in ~w(heartbeat reconcile),
    do: {:noreply, load(socket)}

  def handle_info(event, socket)
      when event in [:permissions_changed, :requests_changed, :reconcile],
      do: {:noreply, load(socket)}

  defp load(socket) do
    result = Incidents.list(socket.assigns.current_scope, socket.assigns.filters)

    workflows =
      WorkflowCatalog.available(socket.assigns.current_scope)
      |> Enum.filter(fn version ->
        Enum.any?(version.definition["views"], &(&1["urgency"] != nil))
      end)

    socket
    |> assign(
      result: Map.delete(result, :rows),
      create_options: Enum.map(workflows, &%{id: &1.workflow_id, name: &1.definition["name"]})
    )
    |> stream(:incidents, result.rows, reset: true)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="page-heading">
        <div>
          <p class="eyebrow">ACOMPANHAMENTO RESTRITO</p><h1>Ocorrências</h1><p>
            Relatos fictícios e comunicação simulada. Este sistema não garante atendimento de emergências.
          </p>
        </div>
      </div>
      <div id="incidents-connection" phx-hook="Collaboration" phx-update="ignore"></div>
      <p id="incident-urgency-status" role="status" aria-live="polite" aria-atomic="true">
        {@result.urgent} ocorrência(s) urgente(s) aberta(s) no seu acesso.
      </p>
      <button
        :for={option <- @create_options}
        id={"new-incident-#{option.id}"}
        class="btn primary"
        phx-click="create"
        phx-value-id={option.id}
        phx-disable-with="Registrando…"
      >Registrar ocorrência fictícia</button>
      <section class="card template-section">
        <h2>Triagem autorizada</h2><p id="incident-count">
          {@result.total} ocorrência(s) disponíveis · {@result.filtered} resultado(s), até 100 exibidos.
        </p>
        <.form for={@form} id="incident-filters" phx-submit="filter">
          <.input
            field={@form[:urgency]}
            label="Urgência"
            type="select"
            prompt="Todas"
            options={["Urgente", "Prioritária", "Rotina"]}
          />
          <.input
            field={@form[:stage]}
            label="Etapa"
            type="select"
            prompt="Todas"
            options={[
              {"Registrada", "draft"},
              {"Triagem", "triage"},
              {"Acompanhamento", "followup"},
              {"Comunicação simulada", "communication"},
              {"Encerrada", "closed"},
              {"Cancelada", "cancelled"}
            ]}
          />
          <button id="filter-incidents" class="btn">Filtrar</button>
        </.form>
        <div id="incidents" phx-update="stream" class="foundation-grid">
          <article :for={{id, incident} <- @streams.incidents} id={id} class="card">
            <h3>
              <.link navigate={~p"/o/#{@current_scope.organization.slug}/solicitacoes/#{incident.id}"}>Ocorrência #{incident.id}</.link>
            </h3>
            <strong>Urgência: {incident.urgency}</strong><p>{incident.stage_label}</p><p>
              Local: {incident.location}
            </p>
          </article>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
