defmodule InstantflowWeb.RequestLive do
  use InstantflowWeb, :live_view
  alias Instantflow.{Delivery, WorkflowRuntime}
  alias InstantflowWeb.RuntimeErrors

  def mount(%{"id" => id}, _session, socket) do
    case Integer.parse(id) do
      {id, ""} when id > 0 and id < 9_223_372_036_854_775_807 ->
        case WorkflowRuntime.get(socket.assigns.current_scope, id) do
          {:ok, data} ->
            if connected?(socket),
              do:
                Phoenix.PubSub.subscribe(
                  Instantflow.PubSub,
                  Delivery.topic(socket.assigns.current_scope.organization_id, id)
                )

            {:ok,
             socket
             |> assign(
               page_title: "Solicitação ##{id}",
               dirty: false,
               stale: false,
               reason: to_form(%{}, as: :action)
             )
             |> load(data)}

          _ ->
            unavailable(socket)
        end

      _ ->
        unavailable(socket)
    end
  end

  def handle_event("draft", %{"section" => values, "key" => key}, socket) do
    if key in socket.assigns.data.editable do
      {:noreply,
       socket
       |> assign(:dirty, true)
       |> assign(:forms, Map.put(socket.assigns.forms, key, to_form(values, as: :section)))
       |> stream_insert(:sections, Enum.find(socket.assigns.data.sections, &(&1.key == key)))}
    else
      {:noreply, put_flash(socket, :error, RuntimeErrors.message(:forbidden))}
    end
  end

  def handle_event("save", %{"section" => values, "key" => key}, socket) do
    data = socket.assigns.data
    section = Enum.find(data.sections, &(&1.key == key))

    if section && key in data.editable do
      definition = Enum.find(data.section_definitions, &(&1["key"] == key))
      values = cast_values(definition, values)

      command = %{
        "operation" => "save_section",
        "key" => Ecto.UUID.generate(),
        "ticket_id" => data.ticket.id,
        "section" => key,
        "values" => values,
        "expected_stage_revision" => data.ticket.stage_revision,
        "expected_section_revision" => section.revision
      }

      socket =
        socket
        |> assign(:forms, Map.put(socket.assigns.forms, key, to_form(values, as: :section)))
        |> stream_insert(:sections, section)

      respond(socket, WorkflowRuntime.command(socket.assigns.current_scope, command))
    else
      {:noreply, put_flash(socket, :error, RuntimeErrors.message(:forbidden))}
    end
  end

  def handle_event("reason", %{"action" => params}, socket),
    do: {:noreply, assign(socket, reason: to_form(params, as: :action), dirty: true)}

  def handle_event("transition", %{"transition" => edge, "action" => params}, socket) do
    data = socket.assigns.data
    socket = assign(socket, :reason, to_form(params, as: :action))

    command = %{
      "operation" => "transition",
      "key" => Ecto.UUID.generate(),
      "ticket_id" => data.ticket.id,
      "transition" => edge,
      "reason" => params["reason"],
      "expected_revision" => data.ticket.revision,
      "section_revisions" => Map.new(data.sections, &{&1.key, &1.revision})
    }

    respond(socket, WorkflowRuntime.command(socket.assigns.current_scope, command))
  end

  def handle_event("retry", %{"id" => id}, socket) do
    # Only message IDs in this authorized projection can be proposed; the context checks permissions again.
    message = Enum.find(socket.assigns.data.deliveries, &(to_string(&1.id) == id))

    if message,
      do: respond(socket, Delivery.retry(socket.assigns.current_scope, message.id)),
      else: {:noreply, put_flash(socket, :error, RuntimeErrors.message(:forbidden))}
  end

  def handle_event("refresh", _, socket), do: refresh(socket)

  def handle_info(
        {:ticket_changed, organization_id, id},
        %{assigns: %{current_scope: %{organization_id: organization_id}}} = socket
      ) do
    case WorkflowRuntime.get(socket.assigns.current_scope, id) do
      {:ok, data} ->
        if socket.assigns.dirty do
          changed = data.ticket.revision != socket.assigns.data.ticket.revision
          socket = assign(socket, :stale, changed)

          socket =
            if changed,
              do: socket,
              else: stream(socket, :deliveries, data.deliveries, reset: true)

          {:noreply, socket}
        else
          {:noreply, load(socket, data)}
        end

      _ ->
        {:noreply, push_navigate(socket, to: ~p"/entrar")}
    end
  end

  def handle_info({:ticket_changed, _, _}, socket), do: {:noreply, socket}

  defp respond(socket, {:ok, _}) do
    socket =
      assign(socket, dirty: false, reason: to_form(%{}, as: :action))
      |> clear_flash()
      |> put_flash(:info, "Ação registrada com sucesso.")

    refresh(socket)
  end

  defp respond(socket, {:error, error}),
    do:
      {:noreply,
       socket
       |> assign(:dirty, true)
       |> clear_flash()
       |> put_flash(:error, RuntimeErrors.message(error))}

  defp refresh(socket) do
    case WorkflowRuntime.get(socket.assigns.current_scope, socket.assigns.data.ticket.id) do
      {:ok, data} ->
        {:noreply, socket |> assign(dirty: false, stale: false) |> load(data)}

      _ ->
        {:noreply,
         push_navigate(socket,
           to: ~p"/o/#{socket.assigns.current_scope.organization.slug}/solicitacoes"
         )}
    end
  end

  defp unavailable(socket),
    do:
      {:ok,
       socket
       |> put_flash(:error, "Solicitação não encontrada ou sem acesso.")
       |> push_navigate(to: ~p"/o/#{socket.assigns.current_scope.organization.slug}/solicitacoes")}

  defp load(socket, data) do
    forms = Map.new(data.sections, &{&1.key, to_form(&1.values, as: :section)})

    socket
    |> assign(data: data, forms: forms)
    |> stream(:sections, data.sections, reset: true)
    |> stream(:events, data.events, reset: true)
    |> stream(:deliveries, data.deliveries, reset: true)
  end

  defp cast_values(definition, values) do
    Map.new(values, fn {key, value} ->
      field = Enum.find(definition["fields"], &(&1["key"] == key))

      cast =
        case {field && field["type"], value} do
          {type, ""} when type not in ["short_text", "long_text"] ->
            nil

          {type, value} when type in ["integer", "money"] ->
            case Integer.parse(value) do
              {number, ""} -> number
              _ -> value
            end

          {"boolean", "true"} ->
            true

          {"boolean", "false"} ->
            false

          _ ->
            value
        end

      {key, cast}
    end)
  end

  defp stage_label(data),
    do: Enum.find(data.version.definition["stages"], &(&1["key"] == data.ticket.stage))["label"]

  defp field_type("long_text"), do: "textarea"
  defp field_type(type) when type in ["money", "integer"], do: "number"
  defp field_type("date"), do: "date"
  defp field_type(type) when type in ["boolean", "single_choice"], do: "select"
  defp field_type(_), do: "text"

  defp options(%{"type" => "boolean"}),
    do: [{"Não informado", ""}, {"Sim", "true"}, {"Não", "false"}]

  defp options(field), do: Map.get(field, "options", [])
  defp delivery_label("failed"), do: "Falhou"
  defp delivery_label("succeeded"), do: "Concluída"
  defp delivery_label(_), do: "Pendente"
  defp operation_label("create"), do: "Solicitação criada"
  defp operation_label("save:" <> _), do: "Formulário salvo"
  defp operation_label(operation), do: operation

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} unsaved={@dirty}>
      <.link navigate={~p"/o/#{@current_scope.organization.slug}/solicitacoes"}>← Todas as solicitações</.link>
      <div class="page-heading request-heading">
        <div>
          <p class="eyebrow">{@data.version.definition["name"]} · VERSÃO {@data.version.number}</p><h1>
            Solicitação #{@data.ticket.id}
          </h1><p>Revisão {@data.ticket.revision} · {stage_label(@data)}</p>
        </div><span class="badge">{stage_label(@data)}</span>
      </div>
      <div :if={@stale} id="stale-warning" class="flash error" role="alert">
        Esta solicitação foi atualizada. Seu rascunho foi preservado.
      </div>
      <button id="refresh-request" class="btn" phx-click="refresh">Recarregar dados {if @dirty,
        do: "(descarta rascunhos)"}</button>
      <div class="request-detail-grid">
        <div id="sections" phx-update="stream">
          <section :for={{id, section} <- @streams.sections} id={id} class="card section-card">
            <% definition = Enum.find(@data.section_definitions, &(&1["key"] == section.key)) %>
            <h2>{definition["label"]}</h2><p>Revisão do formulário: {section.revision}</p><.form
              :if={section.key in @data.editable}
              for={@forms[section.key]}
              id={"section-form-#{section.key}"}
              phx-change="draft"
              phx-submit="save"
              phx-value-key={section.key}
            >
              <.input
                :for={field <- definition["fields"]}
                field={@forms[section.key][field["key"]]}
                label={field["label"]}
                type={field_type(field["type"])}
                options={options(field)}
              /><button class="btn primary" id={"save-#{section.key}"} phx-disable-with="Salvando…">Salvar formulário</button>
            </.form><dl :if={section.key not in @data.editable}>
              <div :for={field <- definition["fields"]}>
                <dt>{field["label"]}</dt><dd>{format_value(section.values[field["key"]])}</dd>
              </div>
            </dl>
          </section>
        </div>
        <aside class="request-actions">
          <section class="card">
            <h2>Próximos passos</h2><p>
              Salve o formulário antes de avançar. Cada ação respeita as permissões e condições do fluxo.
            </p><.form for={@reason} id="transition-form" phx-change="reason" phx-submit="transition">
              <.input
                field={@reason[:reason]}
                label="Motivo (obrigatório para correção, rejeição e cancelamento)"
                type="textarea"
                maxlength="2000"
              /><div class="transition-buttons">
                <button
                  :for={edge <- @data.transitions}
                  id={"transition-#{edge["key"]}"}
                  name="transition"
                  value={edge["key"]}
                  class="btn"
                  phx-disable-with="Registrando…"
                >{edge["label"]}</button>
              </div>
            </.form><p :if={@data.transitions == []}>
              Nenhuma ação disponível para seu perfil nesta etapa.
            </p>
          </section>
          <section class="card">
            <span class="badge sim">◇ Integrações simuladas</span><h2>Entregas</h2><div
              id="deliveries"
              phx-update="stream"
            >
              <div :for={{id, delivery} <- @streams.deliveries} id={id} class="delivery-row">
                <strong>{if delivery.kind == "simulate_notification",
                  do: "Notificação simulada",
                  else: "Criação de acesso simulada"}</strong><p>
                  {delivery_label(delivery.status)} · {delivery.attempts} tentativa(s)
                </p><button
                  :if={
                    delivery.status == "failed" and
                      @current_scope.department_id == @data.ticket.assigned_department_id
                  }
                  id={"retry-#{delivery.id}"}
                  class="btn"
                  phx-click="retry"
                  phx-value-id={delivery.id}
                >Tentar novamente</button>
              </div>
            </div>
          </section>
        </aside>
      </div>
      <section class="card history-card">
        <h2>Histórico</h2><div id="history" phx-update="stream">
          <article :for={{id, event} <- @streams.events} id={id}>
            <strong>{event_label(event, @data)}</strong><small> Pessoa #{event.actor_id} · {Instantflow.LocalTime.format(
              event.inserted_at,
              @current_scope.organization.timezone
            )}</small><p :if={event.reason}>{event.reason}</p>
          </article>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp format_value(nil), do: "Não informado"
  defp format_value(true), do: "Sim"
  defp format_value(false), do: "Não"
  defp format_value(value) when is_binary(value), do: value
  defp format_value(value), do: Jason.encode!(value)

  defp event_label(event, data) do
    case Enum.find(data.version.definition["transitions"], &(&1["key"] == event.operation)) do
      nil -> operation_label(event.operation)
      edge -> edge["label"]
    end
  end
end
