defmodule InstantflowWeb.RequestLive do
  use InstantflowWeb, :live_view
  alias Instantflow.{Delivery, WorkflowRuntime}
  alias Instantflow.Collaboration.{Editor, Presence}
  alias InstantflowWeb.RuntimeErrors

  def mount(%{"id" => raw_id}, _session, socket) do
    case Integer.parse(raw_id) do
      {id, ""} when id > 0 and id < 9_223_372_036_854_775_807 ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(
            Instantflow.PubSub,
            Delivery.topic(socket.assigns.current_scope.organization_id, id)
          )

          Phoenix.PubSub.subscribe(
            Instantflow.PubSub,
            Presence.topic(socket.assigns.current_scope.organization_id, id)
          )
        end

        case WorkflowRuntime.get(socket.assigns.current_scope, id) do
          {:ok, data} ->
            {:ok,
             socket
             |> assign(
               page_title: "Solicitação ##{id}",
               editors: %{},
               dirty: false,
               stale: false,
               active_section: nil,
               review_revision: data.ticket.revision,
               action_key: Ecto.UUID.generate(),
               reason: to_form(%{}, as: :action),
               assignment_form: to_form(%{}, as: :assignment),
               upload_form: to_form(%{}, as: :upload)
             )
             |> allow_upload(:private_document,
               accept: ~w(.pdf .png .jpg .jpeg),
               max_entries: 1,
               max_file_size: 5_242_880
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
    values = form_values(values)

    if key in socket.assigns.data.editable do
      definition = Enum.find(socket.assigns.data.section_definitions, &(&1["key"] == key))
      values = preserve_attachments(definition, socket.assigns.editors[key], values)
      editor = Editor.draft(socket.assigns.editors[key], values)
      Presence.heartbeat(socket.assigns.current_scope, socket.assigns.data.ticket.id, key)
      {:noreply, socket |> assign(active_section: key) |> put_editor(key, editor)}
    else
      refresh(socket)
    end
  end

  def handle_event(
        "recover_draft",
        %{"section" => values, "key" => key, "observed" => observed},
        socket
      ) do
    data = socket.assigns.data
    values = form_values(values)

    with true <- key in data.editable,
         {revision, ""} <- Integer.parse(observed["revision"] || ""),
         {stage_revision, ""} <- Integer.parse(observed["stage_revision"] || ""),
         command_key when is_binary(command_key) and byte_size(command_key) in 1..128 <-
           observed["key"] do
      editor = %{
        socket.assigns.editors[key]
        | values: values,
          revision: revision,
          stage_revision: stage_revision,
          key: command_key,
          dirty: true
      }

      refresh(put_editor(socket, key, editor))
    else
      _ -> refresh(socket)
    end
  end

  def handle_event("save", %{"section" => values, "key" => key}, socket) do
    data = socket.assigns.data
    values = form_values(values)

    if key in data.editable do
      definition = Enum.find(data.section_definitions, &(&1["key"] == key))
      values = preserve_attachments(definition, socket.assigns.editors[key], values)
      editor = Editor.draft(socket.assigns.editors[key], values)

      command = %{
        "operation" => "save_section",
        "key" => editor.key,
        "ticket_id" => data.ticket.id,
        "section" => key,
        "values" => cast_values(definition, values),
        "expected_stage_revision" => editor.stage_revision,
        "expected_section_revision" => editor.revision
      }

      socket = put_editor(socket, key, editor)

      case WorkflowRuntime.command(socket.assigns.current_scope, command) do
        {:ok, result} ->
          # A save acknowledges only this section. Other authorized drafts survive.
          socket =
            assign(socket,
              editors: Map.delete(socket.assigns.editors, key),
              review_revision:
                if(result["revision"] == data.ticket.revision + 1,
                  do: result["revision"],
                  else: socket.assigns.review_revision
                )
            )

          refresh(put_flash(socket, :info, "Formulário salvo."))

        {:error, error} ->
          failure(socket, error)
      end
    else
      refresh(socket)
    end
  end

  def handle_event("compare", %{"key" => key}, socket) do
    case socket.assigns.editors[key] do
      %{conflict: true} = editor ->
        {:noreply, put_editor(socket, key, %{editor | comparing: true})}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("reapply", %{"key" => key}, socket) do
    editor = socket.assigns.editors[key]
    section = Enum.find(socket.assigns.data.sections, &(&1.key == key))

    if editor && editor.comparing && section && key in socket.assigns.data.editable do
      {:noreply,
       put_editor(socket, key, Editor.reapply(editor, section, socket.assigns.data.ticket))}
    else
      refresh(socket)
    end
  end

  def handle_event("discard", %{"key" => key}, socket) do
    refresh(assign(socket, :editors, Map.delete(socket.assigns.editors, key)))
  end

  def handle_event("reason", %{"action" => params}, socket) do
    {:noreply,
     assign(socket, reason: to_form(params, as: :action), action_key: Ecto.UUID.generate())}
  end

  def handle_event("review", _, socket) do
    {:noreply,
     assign(socket,
       review_revision: socket.assigns.data.ticket.revision,
       stale: false,
       action_key: Ecto.UUID.generate()
     )}
  end

  def handle_event("transition", %{"transition" => edge, "action" => params}, socket) do
    data = socket.assigns.data

    if socket.assigns.dirty or socket.assigns.stale do
      failure(socket, :conflict)
    else
      command = %{
        "operation" => "transition",
        "key" => socket.assigns.action_key,
        "ticket_id" => data.ticket.id,
        "transition" => edge,
        "reason" => params["reason"],
        "expected_revision" => socket.assigns.review_revision,
        "section_revisions" => Map.new(data.sections, &{&1.key, &1.revision})
      }

      socket = assign(socket, :reason, to_form(params, as: :action))

      case WorkflowRuntime.command(socket.assigns.current_scope, command) do
        {:ok, result} ->
          refresh(
            assign(socket,
              reason: to_form(%{}, as: :action),
              review_revision: result["revision"],
              action_key: Ecto.UUID.generate()
            )
          )

        {:error, error} ->
          failure(socket, error)
      end
    end
  end

  def handle_event("retry", %{"id" => id}, socket) do
    message = Enum.find(socket.assigns.data.deliveries, &(to_string(&1.id) == id))

    case message && Delivery.retry(socket.assigns.current_scope, message.id) do
      {:ok, _} -> refresh(socket)
      {:error, error} -> failure(socket, error)
      _ -> failure(socket, :forbidden)
    end
  end

  def handle_event("private-upload-change", _, socket), do: {:noreply, socket}

  def handle_event("private-upload", %{"upload" => %{"target" => target}}, socket) do
    if Enum.any?(socket.assigns.attachment_options, fn {_, ref} -> ref == target end) do
      [section, field] = String.split(target, ".")

      results =
        consume_uploaded_entries(socket, :private_document, fn %{path: path}, entry ->
          {:ok,
           Instantflow.PrivateDocuments.upload(
             socket.assigns.current_scope,
             socket.assigns.data.ticket.id,
             section,
             field,
             entry.client_name,
             File.read!(path)
           )}
        end)

      case results do
        [{:ok, document}] ->
          editor = socket.assigns.editors[section]
          editor = Editor.draft(editor, Map.put(editor.values, field, document.object_key))
          refresh(put_editor(socket, section, editor))

        [{:error, error}] ->
          failure(socket, error)

        _ ->
          failure(socket, :invalid_file)
      end
    else
      failure(socket, :forbidden)
    end
  end

  def handle_event("review-private-document", %{"key" => key, "accept" => accept}, socket) do
    case Instantflow.PrivateDocuments.review(socket.assigns.current_scope, key, accept == "true") do
      {:ok, _} -> refresh(socket)
      {:error, error} -> failure(socket, error)
    end
  end

  def handle_event("delete-private-document", %{"key" => key}, socket) do
    case Instantflow.PrivateDocuments.delete(socket.assigns.current_scope, key) do
      {:ok, _} -> refresh(socket)
      {:error, error} -> failure(socket, error)
    end
  end

  def handle_event("assign-section", %{"assignment" => p}, socket) do
    member_id =
      case Integer.parse(p["membership_id"] || "") do
        {id, ""} when id > 0 -> id
        _ -> nil
      end

    data = socket.assigns.data

    case WorkflowRuntime.command(socket.assigns.current_scope, %{
           "operation" => "assign",
           "key" => socket.assigns.action_key,
           "ticket_id" => data.ticket.id,
           "section" => p["section"],
           "membership_id" => member_id,
           "expected_revision" => socket.assigns.review_revision,
           "reason" => p["reason"]
         }) do
      {:ok, result} ->
        refresh(
          assign(socket, action_key: Ecto.UUID.generate(), review_revision: result["revision"])
        )

      {:error, error} ->
        failure(socket, error)
    end
  end

  def handle_event("refresh", _, socket), do: refresh(socket)
  def handle_event("reconcile", _, socket), do: refresh(socket)

  def handle_event("heartbeat", _, socket) do
    if socket.assigns.active_section,
      do:
        Presence.heartbeat(
          socket.assigns.current_scope,
          socket.assigns.data.ticket.id,
          socket.assigns.active_section
        )

    refresh(socket)
  end

  def handle_info({:ticket_changed, organization_id, id}, socket) do
    if socket.assigns.current_scope.organization_id == organization_id and
         socket.assigns.data.ticket.id == id, do: refresh(socket), else: {:noreply, socket}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket),
    do: {:noreply, load_presence(socket)}

  def handle_info(:reconcile, socket), do: refresh(socket)
  def handle_info(:permissions_changed, socket), do: refresh(socket)

  defp failure(socket, error) do
    {:noreply, updated} = refresh(socket)
    {:noreply, updated |> clear_flash() |> put_flash(:error, RuntimeErrors.message(error))}
  end

  defp refresh(socket) do
    case WorkflowRuntime.get(socket.assigns.current_scope, socket.assigns.data.ticket.id) do
      {:ok, data} ->
        {:noreply, load(socket, data)}

      _ ->
        # Remove protected values and drafts before leaving an unavailable record.
        socket =
          Enum.reduce(
            socket.assigns.uploads.private_document.entries,
            socket,
            &cancel_upload(&2, :private_document, &1.ref)
          )

        {:noreply,
         socket
         |> assign(data: nil, editors: %{}, forms: %{}, dirty: false)
         |> redirect(to: ~p"/o/#{socket.assigns.current_scope.organization.slug}/solicitacoes")}
    end
  end

  defp unavailable(socket),
    do:
      {:ok,
       socket
       |> put_flash(:error, "Solicitação não encontrada ou sem acesso.")
       |> push_navigate(to: ~p"/o/#{socket.assigns.current_scope.organization.slug}/solicitacoes")}

  defp load(socket, data) do
    editors = Editor.reconcile(socket.assigns.editors, data)
    forms = Map.new(editors, fn {key, editor} -> {key, to_form(editor.values, as: :section)} end)

    attachment_options =
      for section <- data.section_definitions,
          section["key"] in data.editable,
          field <- section["fields"],
          field["type"] == "attachment",
          do: {section["label"] <> " · " <> field["label"], section["key"] <> "." <> field["key"]}

    socket =
      if attachment_options == [] do
        Enum.reduce(
          socket.assigns.uploads.private_document.entries,
          socket,
          &cancel_upload(&2, :private_document, &1.ref)
        )
      else
        socket
      end

    documents = Instantflow.PrivateDocuments.list(socket.assigns.current_scope, data.ticket.id)

    socket
    |> assign(
      attachment_options: attachment_options,
      document_count: length(documents),
      data: data,
      editors: editors,
      forms: forms,
      dirty: Enum.any?(editors, fn {_, e} -> e.dirty end),
      stale: data.ticket.revision != socket.assigns.review_revision
    )
    |> stream(:private_documents, documents, reset: true)
    |> stream(:assignments, data.assignments, reset: true)
    |> stream(:sections, data.sections, reset: true)
    |> stream(:events, data.events, reset: true)
    |> stream(:deliveries, data.deliveries, reset: true)
    |> load_presence()
  end

  defp load_presence(socket) do
    assign(socket, :presence, Presence.editors(socket.assigns.current_scope, socket.assigns.data))
    |> stream(:sections, socket.assigns.data.sections, reset: true)
  end

  defp put_editor(socket, key, editor) do
    editors = Map.put(socket.assigns.editors, key, editor)

    socket
    |> assign(
      editors: editors,
      dirty: Enum.any?(editors, fn {_, e} -> e.dirty end),
      forms: Map.put(socket.assigns.forms, key, to_form(editor.values, as: :section))
    )
    |> stream_insert(:sections, Enum.find(socket.assigns.data.sections, &(&1.key == key)))
  end

  defp preserve_attachments(definition, editor, values) do
    Enum.reduce(definition["fields"], values, fn field, acc ->
      if field["type"] == "attachment",
        do: Map.put(acc, field["key"], editor.values[field["key"]]),
        else: acc
    end)
  end

  defp document_status("quarantined"), do: "Em quarentena"
  defp document_status("ready"), do: "Liberado"
  defp document_status("rejected"), do: "Recusado"
  defp document_status("deleted"), do: "Excluído"
  defp document_status(_), do: "Expirado"

  defp form_values(values),
    do: Map.reject(values, fn {key, _} -> String.starts_with?(key, "_unused_") end)

  defp cast_values(definition, values) do
    values =
      Enum.reduce(definition["fields"], values, fn field, acc ->
        if field["type"] == "multiple_choice", do: Map.put_new(acc, field["key"], []), else: acc
      end)

    Map.new(values, fn {key, value} ->
      field = Enum.find(definition["fields"], &(&1["key"] == key))

      cast =
        case {field && field["type"], value} do
          {"multiple_choice", ""} ->
            []

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

          {"multiple_choice", values} when is_list(values) ->
            Enum.reject(values, &(&1 == ""))

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
  defp field_type(type) when type in ["boolean", "single_choice", "multiple_choice"], do: "select"
  defp field_type(_), do: "text"

  defp options(%{"type" => "boolean"}),
    do: [{"Não informado", ""}, {"Sim", "true"}, {"Não", "false"}]

  defp options(field), do: Map.get(field, "options", [])
  defp delivery_label("failed"), do: "Falhou"
  defp delivery_label("succeeded"), do: "Concluída"
  defp delivery_label(_), do: "Pendente"
  defp delivery_kind("simulate_payment"), do: "Pagamento simulado"
  defp delivery_kind("simulate_notification"), do: "Notificação simulada"
  defp delivery_kind(_), do: "Criação de acesso simulada"
  defp operation_label("assign:" <> _), do: "Atribuição de responsável atualizada"
  defp operation_label("create"), do: "Solicitação criada"
  defp operation_label("save:" <> _), do: "Formulário salvo"
  defp operation_label(operation), do: operation

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      unsaved={@dirty or (@reason.params["reason"] || "") != ""}
    >
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
      <div id="request-connection" phx-hook="Collaboration" phx-update="ignore"></div>
      <button id="refresh-request" class="btn" phx-click="refresh">Atualizar mantendo rascunhos</button>
      <button :if={@stale} id="review-request" class="btn" phx-click="review">Confirmei a revisão dos dados atuais</button>
      <div class="request-detail-grid">
        <div id="sections" phx-update="stream">
          <section :for={{id, section} <- @streams.sections} id={id} class="card section-card">
            <% definition = Enum.find(@data.section_definitions, &(&1["key"] == section.key)) %>
            <h2>{definition["label"]}</h2><p>Revisão do formulário: {section.revision}</p>
            <p :if={@editors[section.key].dirty} class="presence-note">
              Rascunho não salvo · mantido apenas nesta aba
            </p>
            <button
              :if={@editors[section.key].dirty and not @editors[section.key].conflict}
              class="btn"
              phx-click="discard"
              phx-value-key={section.key}
            >Descartar meu rascunho</button>
            <p
              :for={
                peer <-
                  Enum.filter(
                    @presence,
                    &(&1.section == section.key and &1.user_id != @current_scope.user_id)
                  )
              }
              class="presence-note"
            >
              {peer.name} está editando este formulário.
            </p>
            <div
              :if={@editors[section.key].conflict}
              id={"conflict-#{section.key}"}
              class="conflict-panel"
              role="status"
            >
              <strong>Há alterações neste formulário. Seu rascunho foi preservado.</strong>
              <button class="btn" phx-click="compare" phx-value-key={section.key}>Revisar alterações</button>
              <div :if={@editors[section.key].comparing} id={"comparison-#{section.key}"}>
                <h3>Versão salva por outra pessoa</h3>
                <dl>
                  <div :for={field <- definition["fields"]}>
                    <dt>{field["label"]}</dt><dd>{format_value(section.values[field["key"]])}</dd>
                  </div>
                </dl>
                <button
                  :if={section.key in @data.editable}
                  class="btn"
                  phx-click="reapply"
                  phx-value-key={section.key}
                >Reaplicar minhas alterações</button>
              </div>
              <button class="btn" phx-click="discard" phx-value-key={section.key}>Descartar meu rascunho</button>
            </div><.form
              :if={section.key in @data.editable}
              for={@forms[section.key]}
              id={"section-form-#{section.key}"}
              phx-change="draft"
              phx-auto-recover="recover_draft"
              phx-submit="save"
              phx-value-key={section.key}
            >
              <input type="hidden" name="observed[revision]" value={@editors[section.key].revision} />
              <input
                type="hidden"
                name="observed[stage_revision]"
                value={@editors[section.key].stage_revision}
              />
              <input type="hidden" name="observed[key]" value={@editors[section.key].key} />
              <.input
                :for={field <- definition["fields"]}
                field={@forms[section.key][field["key"]]}
                id={"section-#{section.key}-#{field["key"]}"}
                label={field["label"]}
                type={field_type(field["type"])}
                multiple={field["type"] == "multiple_choice"}
                disabled={field["type"] in ~w(directory_reference attachment)}
                min={if field["type"] == "money", do: 0}
                step={if field["type"] in ~w(integer money), do: 1}
                placeholder={if field["type"] == "datetime", do: "2026-10-20T14:00:00-03:00"}
                options={options(field)}
              /><button
                class="btn primary"
                id={"save-#{section.key}"}
                data-authoritative
                phx-disable-with="Salvando…"
              >Salvar formulário</button>
            </.form><dl :if={section.key not in @data.editable}>
              <div :for={field <- definition["fields"]}>
                <dt>{field["label"]}</dt><dd>{format_value(section.values[field["key"]])}</dd>
              </div>
            </dl>
          </section>
        </div>
        <aside class="request-actions">
          <section :if={@attachment_options != [] or @document_count > 0} class="card">
            <h2>Documentos privados fictícios</h2><p>
              PDF, PNG ou JPEG até 5 MiB. Quarentena e liberação manual; verificação limitada, sem antivírus.
            </p>
            <.form
              :if={@attachment_options != []}
              for={@upload_form}
              id="private-upload-form"
              phx-change="private-upload-change"
              phx-submit="private-upload"
            >
              <.input
                field={@upload_form[:target]}
                type="select"
                label="Campo do documento"
                options={@attachment_options}
              />
              <label for={@uploads.private_document.ref}>Escolher documento fictício</label>
              <.live_file_input upload={@uploads.private_document} />
              <div :for={entry <- @uploads.private_document.entries}>
                <span>{entry.client_name}</span><p :for={
                  _ <- upload_errors(@uploads.private_document, entry)
                }>
                  Arquivo não aceito: confirme o formato e o limite de 5 MiB.
                </p>
              </div>
              <p :for={error <- upload_errors(@uploads.private_document)}>
                Arquivo recusado: {error}
              </p>
              <button
                id="upload-private-document"
                class="btn"
                disabled={@uploads.private_document.entries == []}
              >Enviar para quarentena</button>
            </.form>
            <div id="private-documents" phx-update="stream">
              <article :for={{id, doc} <- @streams.private_documents} id={id}>
                <strong>{doc.filename}</strong><p>{document_status(doc.status)}</p>
                <.link
                  :if={doc.status == "ready"}
                  id={"download-private-#{doc.id}"}
                  href={~p"/o/#{@current_scope.organization.slug}/documentos/#{doc.object_key}"}
                >Baixar documento privado</.link>
                <button
                  :if={doc.status == "quarantined" and doc.section_key in @data.editable}
                  id={"release-private-#{doc.id}"}
                  class="btn"
                  phx-click="review-private-document"
                  phx-value-key={doc.object_key}
                  phx-value-accept="true"
                >Revisei: liberar documento fictício</button>
                <button
                  :if={doc.status == "quarantined" and doc.section_key in @data.editable}
                  id={"reject-private-#{doc.id}"}
                  class="btn"
                  phx-click="review-private-document"
                  phx-value-key={doc.object_key}
                  phx-value-accept="false"
                >Recusar documento</button>
                <button
                  :if={doc.section_key in @data.editable and doc.status in ~w(quarantined ready)}
                  id={"delete-private-#{doc.id}"}
                  class="btn"
                  phx-click="delete-private-document"
                  phx-value-key={doc.object_key}
                >Excluir conteúdo</button>
              </article>
            </div>
          </section>
          <div id="section-assignments" phx-update="stream">
            <section :for={{id, assignment} <- @streams.assignments} id={id} class="card">
              <h2>Atribuir: {assignment.label}</h2>
              <.form
                for={@assignment_form}
                id={"assignment-form-#{assignment.id}"}
                phx-submit="assign-section"
              >
                <input type="hidden" name="assignment[section]" value={assignment.id} />
                <.input
                  name="assignment[membership_id]"
                  id={"assignment-member-#{assignment.id}"}
                  label="Responsável local"
                  type="select"
                  options={assignment.options}
                  prompt="Sem responsável / revogar"
                  value={assignment.membership_id}
                />
                <.input
                  field={@assignment_form[:reason]}
                  id={"assignment-reason-#{assignment.id}"}
                  label="Motivo da atribuição ou revogação"
                  required
                  maxlength="2000"
                />
                <button
                  id={"assign-#{assignment.id}"}
                  class="btn"
                  disabled={@dirty or @stale or not (assignment.editable? or assignment.revocable?)}
                >Salvar atribuição</button>
              </.form>
            </section>
          </div>
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
                  data-authoritative
                  disabled={@dirty or @stale}
                  data-blocked={to_string(@dirty or @stale)}
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
                <strong>{delivery_kind(delivery.kind)}</strong><p>
                  {delivery_label(delivery.status)} · {delivery.attempts} tentativa(s)
                </p><button
                  :if={delivery.status == "failed" and @data.can_retry}
                  id={"retry-#{delivery.id}"}
                  class="btn"
                  data-authoritative
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
