defmodule InstantflowWeb.ParticipantLive do
  use InstantflowWeb, :live_view
  alias Instantflow.WorkflowRuntime.{ParticipantPages, Projections}
  alias Instantflow.{Delivery, WorkflowRuntime}

  def mount(params, _, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        Instantflow.PubSub,
        WorkflowRuntime.list_topic(socket.assigns.current_scope)
      )

      if id = number(params["id"]),
        do:
          Phoenix.PubSub.subscribe(
            Instantflow.PubSub,
            Delivery.topic(socket.assigns.current_scope.organization_id, id)
          )
    end

    {:ok,
     socket
     |> assign(
       page_title: "Participação",
       data: nil,
       forms: %{},
       drafts: %{},
       workflow_id: number(params["workflow_id"]),
       page_key: params["page_key"],
       record_id: number(params["id"]),
       page: 1,
       pages: 1,
       total: 0,
       command_key: Ecto.UUID.generate(),
       action_form: to_form(%{}, as: :action),
       upload_form: to_form(%{}, as: :upload)
     )
     |> allow_upload(:document,
       accept: ~w(.pdf .png .jpg .jpeg),
       max_entries: 1,
       max_file_size: 5_242_880
     )
     |> stream(:records, [])
     |> stream(:fields, [])
     |> stream(:documents, [])
     |> stream(:history, [])
     |> stream(:actions, [])}
  end

  def handle_params(params, _, socket) do
    workflow_id = number(params["workflow_id"])
    record_id = number(params["id"])

    cond do
      is_nil(workflow_id) or (params["id"] && is_nil(record_id)) ->
        {:noreply,
         redirect(socket, to: ~p"/o/#{socket.assigns.current_scope.organization.slug}/processos")}

      workflow_id != socket.assigns.workflow_id or record_id != socket.assigns.record_id ->
        # A new record gets a new mount and subscription, never retained forms
        # and data from a different URL target.
        path =
          if record_id,
            do:
              ~p"/o/#{socket.assigns.current_scope.organization.slug}/processos/#{workflow_id}/participacao/#{params["page_key"]}/registros/#{record_id}",
            else:
              ~p"/o/#{socket.assigns.current_scope.organization.slug}/processos/#{workflow_id}/participacao/#{params["page_key"]}"

        {:noreply, push_navigate(socket, to: path)}

      true ->
        {:noreply, socket |> assign(:page_key, params["page_key"]) |> load()}
    end
  end

  def handle_info(_, socket), do: {:noreply, load(socket)}

  def handle_event(event, _, socket) when event in ~w(reconcile heartbeat),
    do: {:noreply, load(socket)}

  def handle_event("page", %{"page" => page}, socket),
    do: {:noreply, socket |> assign(:page, number(page) || 1) |> load()}

  def handle_event("draft", %{"ref" => ref, "field" => params}, socket) do
    field =
      socket.assigns.data &&
        Enum.find(socket.assigns.data.fields, &(&1.ref == ref and &1.editable?))

    if field do
      draft =
        socket.assigns.drafts[ref] ||
          %{section_revision: field.revision, stage_revision: socket.assigns.data.stage_revision}

      {:noreply,
       socket
       |> assign(:forms, Map.put(socket.assigns.forms, ref, to_form(params, as: :field)))
       |> assign(:drafts, Map.put(socket.assigns.drafts, ref, draft))}
    else
      {:noreply, load(socket)}
    end
  end

  def handle_event("save", %{"ref" => ref, "field" => %{"value" => value}}, socket) do
    field =
      socket.assigns.data &&
        Enum.find(socket.assigns.data.fields, &(&1.ref == ref and &1.editable?))

    if field do
      observed =
        socket.assigns.drafts[ref] ||
          %{section_revision: field.revision, stage_revision: socket.assigns.data.stage_revision}

      result =
        ParticipantPages.save(
          socket.assigns.current_scope,
          socket.assigns.workflow_id,
          socket.assigns.page_key,
          socket.assigns.record_id,
          field.section,
          %{field.key => cast(field.type, value)},
          observed,
          socket.assigns.command_key
        )

      socket =
        if match?({:ok, _}, result),
          do: assign(socket, :drafts, Map.delete(socket.assigns.drafts, ref)),
          else: socket

      {:noreply, result(socket, result)}
    else
      {:noreply, load(socket)}
    end
  end

  def handle_event("transition", %{"action" => params}, socket) do
    result =
      ParticipantPages.transition(
        socket.assigns.current_scope,
        socket.assigns.workflow_id,
        socket.assigns.page_key,
        socket.assigns.record_id,
        params["edge"],
        number(params["revision"]),
        params["reason"],
        socket.assigns.command_key
      )

    {:noreply, result(socket, result)}
  end

  def handle_event("upload", %{"upload" => params}, socket) do
    results =
      consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
        result =
          ParticipantPages.upload(
            socket.assigns.current_scope,
            socket.assigns.workflow_id,
            socket.assigns.page_key,
            socket.assigns.record_id,
            params["target"],
            entry.client_name,
            File.read!(path),
            socket.assigns.command_key
          )

        {:ok, result}
      end)

    {:noreply, result(socket, List.first(results) || {:error, :invalid_file})}
  end

  defp result(socket, {:ok, _}),
    do: socket |> assign(:command_key, Ecto.UUID.generate()) |> load()

  defp result(socket, {:error, reason}),
    do: socket |> load() |> put_flash(:error, InstantflowWeb.RuntimeErrors.message(reason))

  defp load(%{assigns: %{record_id: nil}} = socket) do
    data =
      Projections.participant_search(
        socket.assigns.current_scope,
        socket.assigns.workflow_id,
        socket.assigns.page_key,
        %{"page" => socket.assigns.page}
      )

    socket
    |> assign(page: data.page, pages: data.pages, total: data.total)
    |> stream(:records, data.rows, reset: true)
  end

  defp load(socket) do
    case ParticipantPages.get(
           socket.assigns.current_scope,
           socket.assigns.workflow_id,
           socket.assigns.page_key,
           socket.assigns.record_id
         ) do
      {:ok, data} ->
        requested_page = socket.assigns.page_key
        editable = for field <- data.fields, field.editable?, do: field.ref
        drafts = Map.take(socket.assigns.drafts, editable)

        forms =
          Map.new(data.fields, fn field ->
            form =
              if drafts[field.ref],
                do: socket.assigns.forms[field.ref],
                else: to_form(%{"value" => field.value}, as: :field)

            {field.ref, form}
          end)

        socket =
          if socket.assigns.data && socket.assigns.data.uploads != data.uploads,
            do: clear_uploads(socket),
            else: socket

        socket =
          socket
          |> assign(
            data: Map.drop(data, [:fields, :documents, :history, :actions]),
            page_title: data.label,
            page_key: data.page_key,
            forms: forms,
            drafts: drafts,
            action_form: to_form(%{"revision" => data.revision}, as: :action)
          )
          |> stream(:fields, data.fields, reset: true)
          |> stream(:documents, data.documents, reset: true)
          |> stream(:history, data.history, reset: true)
          |> stream(:actions, data.actions, reset: true)

        # Retain only the currently projected field metadata used by events.
        socket = assign(socket, :data, Map.put(socket.assigns.data, :fields, data.fields))

        if requested_page == data.page_key do
          socket
        else
          push_patch(socket,
            to:
              ~p"/o/#{socket.assigns.current_scope.organization.slug}/processos/#{data.workflow_id}/participacao/#{data.page_key}/registros/#{data.id}"
          )
        end

      _ ->
        socket
        |> clear_uploads()
        |> assign(
          data: nil,
          forms: %{},
          drafts: %{},
          action_form: to_form(%{}, as: :action),
          upload_form: to_form(%{}, as: :upload)
        )
        |> stream(:fields, [], reset: true)
        |> stream(:documents, [], reset: true)
        |> stream(:history, [], reset: true)
        |> stream(:actions, [], reset: true)
        |> redirect(to: ~p"/o/#{socket.assigns.current_scope.organization.slug}/processos")
    end
  end

  defp clear_uploads(socket),
    do:
      Enum.reduce(
        socket.assigns.uploads.document.entries,
        socket,
        &cancel_upload(&2, :document, &1.ref)
      )

  defp number(value) when is_binary(value) and byte_size(value) <= 18 do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> nil
    end
  end

  defp number(_), do: nil
  defp cast(type, "") when type not in ~w(short_text long_text), do: nil
  defp cast("boolean", "true"), do: true
  defp cast("boolean", "false"), do: false

  defp cast(type, value) when type in ~w(integer money) and is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> value
    end
  end

  defp cast(_, value), do: value
  defp input_type("long_text"), do: "textarea"
  defp input_type(type) when type in ~w(integer money), do: "number"
  defp input_type(type) when type in ~w(boolean single_choice multiple_choice), do: "select"
  defp input_type("date"), do: "date"
  defp input_type(_), do: "text"
  defp options(%{type: "boolean"}), do: [{"Sim", "true"}, {"Não", "false"}]
  defp options(field), do: field.options
  defp display(nil), do: "—"
  defp display(values) when is_list(values), do: Enum.join(values, ", ")
  defp display(value), do: to_string(value)

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1>{@page_title}</h1>
      <.link
        id="participant-processes"
        navigate={~p"/o/#{@current_scope.organization.slug}/processos"}
      >Processos</.link>
      <div id="participant-connection" phx-hook="Collaboration" phx-update="ignore"></div>
      <%= if is_nil(@record_id) do %>
        <p id="participant-count">{@total} registro(s) disponível(is)</p>
        <div id="participant-records" phx-update="stream">
          <article :for={{dom_id, row} <- @streams.records} id={dom_id} class="card">
            <h2>{row.label} · #{row.id}</h2><p :if={row.status}>{row.status}</p>
            <.link
              id={"participant-open-#{row.id}"}
              navigate={
                ~p"/o/#{@current_scope.organization.slug}/processos/#{@workflow_id}/participacao/#{@page_key}/registros/#{row.id}"
              }
            >Abrir</.link>
          </article>
        </div>
        <nav :if={@pages > 1} id="participant-pagination">
          <button
            id="participant-previous"
            phx-click="page"
            phx-value-page={@page - 1}
            disabled={@page <= 1}
          >Anterior</button>
          <span>{@page} / {@pages}</span>
          <button
            id="participant-next"
            phx-click="page"
            phx-value-page={@page + 1}
            disabled={@page >= @pages}
          >Próxima</button>
        </nav>
      <% else %>
        <section :if={@data} id="participant-record" class="card">
          <h2>Registro #{@record_id}</h2><p :if={@data.status} id="participant-status">
            {@data.status}
          </p>
          <div id="participant-fields" phx-update="stream">
            <div :for={{dom_id, field} <- @streams.fields} id={dom_id}>
              <%= if field.editable? do %>
                <.form
                  for={@forms[field.ref]}
                  id={"participant-field-#{field.ref}"}
                  phx-change="draft"
                  phx-submit="save"
                >
                  <input type="hidden" name="ref" value={field.ref} />
                  <.input
                    field={@forms[field.ref][:value]}
                    label={field.label}
                    type={input_type(field.type)}
                    options={options(field)}
                    multiple={field.type == "multiple_choice"}
                  />
                  <button id={"participant-save-#{field.ref}"} class="btn">Salvar</button>
                </.form>
              <% else %>
                <p>{field.label}: {display(field.value)}</p>
              <% end %>
            </div>
          </div>
          <.form
            :if={@data.uploads != []}
            for={@upload_form}
            id="participant-upload"
            phx-submit="upload"
          >
            <.input
              field={@upload_form[:target]}
              type="select"
              label="Documento"
              options={@data.uploads}
            />
            <.live_file_input upload={@uploads.document} />
            <button id="participant-upload-submit" class="btn">Enviar documento</button>
          </.form>
          <div id="participant-documents" phx-update="stream">
            <article :for={{dom_id, doc} <- @streams.documents} id={dom_id}>
              <span>{doc.filename} · {doc.status}</span>
              <.link
                :if={doc.status == "ready"}
                id={"participant-download-#{doc.id}"}
                href={~p"/o/#{@current_scope.organization.slug}/documentos/#{doc.object_key}"}
              >Baixar</.link>
            </article>
          </div>
          <div id="participant-actions" phx-update="stream">
            <.form
              :for={{dom_id, action} <- @streams.actions}
              for={@action_form}
              id={dom_id}
              phx-submit="transition"
            >
              <input type="hidden" name="action[edge]" value={action.id} />
              <input type="hidden" name="action[revision]" value={@data.revision} />
              <.input :if={action.reason?} field={@action_form[:reason]} label="Motivo" />
              <button id={"participant-action-#{action.id}"} class="btn">{action.label}</button>
            </.form>
          </div>
          <div id="participant-history" phx-update="stream">
            <p :for={{dom_id, event} <- @streams.history} id={dom_id}>
              {event.label} · {event.inserted_at}
            </p>
          </div>
        </section>
      <% end %>
    </Layouts.app>
    """
  end
end
