defmodule InstantflowWeb.EnrollmentLive do
  use InstantflowWeb, :live_view
  alias Instantflow.{Enrollment, Identity, PrivateDocuments, WorkflowCatalog}
  alias InstantflowWeb.RuntimeErrors

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Matrículas",
       data: nil,
       dirty: false,
       token: nil,
       staff: Enrollment.staff?(socket.assigns.current_scope),
       application: to_form(%{}, as: :application),
       invitation: to_form(%{}, as: :invitation),
       message: to_form(%{}, as: :message),
       setup: to_form(%{}, as: :setup),
       upload_form: to_form(%{}, as: :upload),
       create_form: to_form(%{}, as: :create),
       form_revision: nil,
       form_stage_revision: nil,
       command_key: Ecto.UUID.generate()
     )
     |> allow_upload(:document,
       accept: ~w(.pdf .png .jpg .jpeg),
       max_entries: 1,
       max_file_size: 5_242_880
     )}
  end

  def handle_params(params, _uri, socket) do
    # Route changes discard the previous record's form and upload state.
    socket =
      Enum.reduce(
        socket.assigns.uploads.document.entries,
        socket,
        &cancel_upload(&2, :document, &1.ref)
      )

    socket =
      assign(socket,
        data: nil,
        dirty: false,
        token: nil,
        application: to_form(%{}, as: :application)
      )

    case params["id"] do
      nil ->
        {:noreply, load_list(socket)}

      raw ->
        case Integer.parse(raw) do
          {id, ""} when id > 0 and id < 9_223_372_036_854_775_807 -> load_record(socket, id)
          _ -> unavailable(socket)
        end
    end
  end

  def handle_event("install", %{"setup" => params}, socket) do
    departments =
      Map.new(~w(admissions academic finance it), fn role ->
        {role <> "_department", parse_id(params[role])}
      end)

    result = Enrollment.install(socket.assigns.current_scope, departments)
    finish(socket, result)
  end

  def handle_event("create", %{"create" => params}, socket) do
    case Enrollment.create(
           socket.assigns.current_scope,
           parse_id(params["workflow_id"]),
           Ecto.UUID.generate()
         ) do
      {:ok, e} ->
        {:noreply,
         push_navigate(socket,
           to: ~p"/o/#{socket.assigns.current_scope.organization.slug}/matriculas/#{e.id}"
         )}

      error ->
        finish(socket, error)
    end
  end

  def handle_event("invite", %{"invitation" => params}, socket) do
    case Enrollment.invite(socket.assigns.current_scope, socket.assigns.data.id, params["email"]) do
      {:ok, result} -> {:noreply, assign(socket, :token, result.token)}
      error -> finish(socket, error)
    end
  end

  def handle_event("verify", %{"id" => id, "active" => active}, socket),
    do:
      finish(
        socket,
        Enrollment.verify(socket.assigns.current_scope, parse_id(id), active == "true")
      )

  def handle_event("message", %{"message" => params}, socket),
    do:
      finish(
        socket,
        Enrollment.public_message(
          socket.assigns.current_scope,
          socket.assigns.data.id,
          params["text"] || ""
        )
      )

  def handle_event("draft", %{"application" => params}, socket),
    do: {:noreply, assign(socket, application: to_form(params, as: :application), dirty: true)}

  def handle_event("save", %{"application" => params}, socket) do
    values =
      Map.take(params, ~w(student_name guardian_name school_year document))
      |> Map.reject(fn {_, v} -> v == "" end)

    # Preserve the object reference unless an explicitly selected upload replaces it.
    result =
      Enrollment.save(
        socket.assigns.current_scope,
        socket.assigns.data.id,
        values,
        socket.assigns.form_stage_revision,
        socket.assigns.form_revision,
        socket.assigns.command_key
      )

    case result do
      {:ok, _} ->
        finish(assign(socket, dirty: false, command_key: Ecto.UUID.generate()), result)

      error ->
        finish(assign(socket, application: to_form(params, as: :application), dirty: true), error)
    end
  end

  def handle_event("submit", _, socket) do
    if socket.assigns.dirty do
      finish(socket, {:error, :conflict})
    else
      d = socket.assigns.data

      finish(
        socket,
        Enrollment.submit(
          socket.assigns.current_scope,
          d.id,
          d.revision,
          d.section_revision,
          Ecto.UUID.generate()
        )
      )
    end
  end

  def handle_event("upload_change", _, socket), do: {:noreply, socket}

  def handle_event("upload", _, socket) do
    results =
      consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
        result =
          Enrollment.upload(
            socket.assigns.current_scope,
            socket.assigns.data.id,
            entry.client_name,
            File.read!(path)
          )

        {:ok, result}
      end)

    case results do
      [{:ok, document}] ->
        params = Map.put(socket.assigns.application.params, "document", document.object_key)
        socket = assign(socket, application: to_form(params, as: :application), dirty: true)
        finish(socket, {:ok, document})

      [error] ->
        finish(socket, error)

      _ ->
        finish(socket, {:error, :invalid_file})
    end
  end

  def handle_event("review_document", %{"key" => key, "accept" => accept}, socket),
    do:
      finish(socket, PrivateDocuments.review(socket.assigns.current_scope, key, accept == "true"))

  def handle_event("delete_document", %{"key" => key}, socket),
    do: finish(socket, PrivateDocuments.delete(socket.assigns.current_scope, key))

  def handle_event("refresh", _, socket), do: refresh(socket)
  def handle_event("discard", _, socket), do: refresh(assign(socket, dirty: false))

  def handle_info(event, socket)
      when event in [:reconcile, :permissions_changed, :enrollments_changed], do: refresh(socket)

  defp finish(socket, {:error, error}),
    do: {:noreply, put_flash(socket, :error, RuntimeErrors.message(error))}

  defp finish(socket, {:ok, _}) do
    refresh(
      put_flash(
        socket,
        :info,
        "Ação registrada. Integrações e documentos desta demonstração são fictícios."
      )
    )
  end

  defp refresh(%{assigns: %{data: nil}} = socket), do: {:noreply, load_list(socket)}
  defp refresh(socket), do: load_record(socket, socket.assigns.data.id)

  defp load_list(socket) do
    a = socket.assigns.current_scope

    versions =
      WorkflowCatalog.available(a)
      |> Enum.filter(&(&1.definition["template_key"] == "enrollment"))

    socket
    |> assign(
      data: nil,
      departments: Identity.departments(a),
      workflows: Enum.map(versions, &{&1.definition["name"], &1.workflow_id})
    )
    |> stream(:enrollments, Enrollment.list(a), reset: true)
  end

  defp load_record(socket, id) do
    case Enrollment.get(socket.assigns.current_scope, id) do
      {:ok, data} ->
        socket =
          if socket.assigns.dirty and data.editable do
            socket
          else
            assign(socket,
              application: to_form(data.values, as: :application),
              dirty: false,
              form_revision: data.section_revision,
              form_stage_revision: data.stage_revision
            )
          end

        {:noreply,
         socket
         |> assign(
           data: data,
           staff: Enrollment.staff?(socket.assigns.current_scope),
           message: to_form(%{"text" => data.public_message}, as: :message),
           document_options:
             Enrollment.documents(socket.assigns.current_scope, id)
             |> Enum.filter(&(&1.status in ["quarantined", "ready"]))
             |> Enum.map(&{&1.filename, &1.object_key})
         )
         |> stream(:documents, Enrollment.documents(socket.assigns.current_scope, id),
           reset: true
         )
         |> stream(:guardians, Enrollment.guardians(socket.assigns.current_scope, id),
           reset: true
         )}

      _ ->
        unavailable(socket)
    end
  end

  defp unavailable(socket),
    do:
      {:noreply,
       socket
       |> assign(data: nil, application: to_form(%{}, as: :application), dirty: false)
       |> redirect(to: ~p"/o/#{socket.assigns.current_scope.organization.slug}/matriculas")}

  defp parse_id(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {id, ""} when id > 0 and id < 9_223_372_036_854_775_807 -> id
      _ -> -1
    end
  end

  defp parse_id(_), do: -1
  defp status("quarantined"), do: "Em quarentena: aguarda revisão da secretaria"
  defp status("ready"), do: "Pronto para verificação"
  defp status("rejected"), do: "Recusado: envie outro documento"
  defp status(_), do: "Indisponível"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} unsaved={@dirty}>
      <div class="page-heading">
        <div>
          <p class="eyebrow">PORTAL DE MATRÍCULAS</p><h1>Matrículas</h1><p>
            Dados fictícios · pagamentos, notificações e criação de acesso simulados.
          </p>
        </div>
      </div>
      <%= if @data do %>
        <.link patch={~p"/o/#{@current_scope.organization.slug}/matriculas"}>← Voltar às matrículas</.link>
        <section class="card" id="enrollment-status">
          <h2>{@data.status}</h2><p id="public-message">{@data.public_message}</p>
          <.link
            :if={@staff}
            id="internal-enrollment"
            navigate={~p"/o/#{@current_scope.organization.slug}/solicitacoes/#{@data.ticket_id}"}
          >Abrir análise interna e próximos passos</.link>
          <button id="refresh-enrollment" class="btn" phx-click="refresh">Atualizar</button>
        </section>
        <section :if={not @staff} class="card">
          <.form for={@application} id="enrollment-form" phx-change="draft" phx-submit="save">
            <.input
              field={@application[:student_name]}
              label="Nome do estudante"
              disabled={not @data.editable}
              maxlength="200"
            />
            <.input
              field={@application[:guardian_name]}
              label="Nome do responsável"
              disabled={not @data.editable}
              maxlength="200"
            />
            <.input
              field={@application[:school_year]}
              label="Ano/série"
              disabled={not @data.editable}
              maxlength="200"
            />
            <.input
              field={@application[:document]}
              type="select"
              label="Documento selecionado"
              disabled={not @data.editable}
              options={@document_options}
              prompt="Selecione um documento"
            />
            <p :if={@dirty} id="enrollment-unsaved">
              Há alterações não salvas. Salve antes de enviar.
            </p>
            <button
              :if={@data.editable}
              id="save-enrollment"
              class="btn primary"
              phx-disable-with="Salvando…"
            >Salvar dados</button>
          </.form>
          <button :if={@dirty} id="discard-enrollment" class="btn" phx-click="discard">Descartar alterações e rever dados atuais</button>
          <button
            :if={@data.editable}
            id="submit-enrollment"
            class="btn primary"
            phx-click="submit"
            disabled={@dirty}
          >Enviar para verificação</button>
        </section>
        <section class="card">
          <h2>Documentos privados</h2><p>
            Somente arquivos fictícios. PDF, PNG ou JPEG, até 5 MB. Revisão manual obrigatória; expiração em 30 dias.
          </p>
          <.form
            :if={@data.editable}
            for={@upload_form}
            id="document-upload-form"
            phx-change="upload_change"
            phx-submit="upload"
          >
            <.live_file_input upload={@uploads.document} />
            <p :for={error <- upload_errors(@uploads.document)}>Arquivo não aceito: {error}</p>
            <div :for={entry <- @uploads.document.entries}>
              <p>{entry.client_name} · {entry.progress}%</p><p :for={
                _ <- upload_errors(@uploads.document, entry)
              }>
                Arquivo inválido ou excede 5 MB.
              </p>
            </div>
            <button id="upload-document" class="btn" disabled={@uploads.document.entries == []}>Enviar para quarentena</button>
          </.form>
          <div id="enrollment-documents" phx-update="stream">
            <article :for={{id, doc} <- @streams.documents} id={id}>
              <strong>{doc.filename}</strong><p>{status(doc.status)}</p>
              <.link
                :if={doc.status == "ready"}
                id={"download-#{doc.id}"}
                href={~p"/o/#{@current_scope.organization.slug}/documentos/#{doc.object_key}"}
              >Baixar documento privado</.link>
              <button
                :if={@staff and doc.status == "quarantined"}
                id={"accept-document-#{doc.id}"}
                class="btn"
                phx-click="review_document"
                phx-value-key={doc.object_key}
                phx-value-accept="true"
              >Revisei: liberar documento fictício</button>
              <button
                :if={@staff and doc.status == "quarantined"}
                class="btn"
                phx-click="review_document"
                phx-value-key={doc.object_key}
                phx-value-accept="false"
              >Recusar documento</button>
              <button
                :if={@data.editable}
                class="btn"
                phx-click="delete_document"
                phx-value-key={doc.object_key}
              >Excluir conteúdo</button>
            </article>
          </div>
        </section>
        <section :if={@staff} class="card">
          <h2>Responsáveis e comunicação pública</h2>
          <.form for={@invitation} id="guardian-invitation-form" phx-submit="invite">
            <.input
              field={@invitation[:email]}
              type="email"
              label="E-mail fictício do responsável"
              required
            /><button class="btn">Gerar convite simulado</button>
          </.form>
          <p :if={@token} id="guardian-invitation-token">
            Convite simulado (48 horas): <code>{@token}</code>. Ative em /convite. Depois confirme manualmente o vínculo.
          </p>
          <div id="guardian-links" phx-update="stream">
            <article :for={{id, link} <- @streams.guardians} id={id}>
              <p>
                {link.membership.user.name} · {if link.active and link.verified_at,
                  do: "Verificado",
                  else: "Sem acesso"}
              </p><button
                id={"verify-guardian-#{link.id}"}
                class="btn"
                phx-click="verify"
                phx-value-id={link.id}
                phx-value-active="true"
              >Verifiquei o vínculo</button><button
                class="btn"
                phx-click="verify"
                phx-value-id={link.id}
                phx-value-active="false"
              >Revogar vínculo</button>
            </article>
          </div>
          <.form for={@message} id="parent-message-form" phx-submit="message">
            <.input
              field={@message[:text]}
              type="textarea"
              label="Mensagem pública ao responsável (não copie notas internas)"
              maxlength="2000"
            /><button class="btn">Publicar mensagem ao responsável</button>
          </.form>
        </section>
      <% else %>
        <section :if={@staff} class="card">
          <h2>Nova matrícula</h2>
          <.form for={@create_form} id="create-enrollment-form" phx-submit="create">
            <.input
              field={@create_form[:workflow_id]}
              type="select"
              label="Fluxo publicado"
              options={@workflows}
              prompt="Selecione"
              required
            /><button class="btn primary">Abrir matrícula e convidar responsável</button>
          </.form>
          <details :if={@current_scope.role == "admin"}>
            <summary>Instalar modelo de matrícula nesta escola</summary><.form
              for={@setup}
              id="install-enrollment-form"
              phx-submit="install"
            >
              <.input
                :for={
                  {key, label} <- [
                    {"admissions", "Secretaria"},
                    {"academic", "Coordenação"},
                    {"finance", "Financeiro"},
                    {"it", "TI"}
                  ]
                }
                field={@setup[key]}
                type="select"
                label={label}
                options={Enum.map(@departments, &{&1.name, &1.id})}
                required
                prompt="Selecione o departamento local"
              /><button class="btn">Publicar modelo de demonstração</button>
            </.form>
          </details>
        </section>
        <div id="enrollment-list" phx-update="stream">
          <p id="enrollment-empty" class="stream-empty">
            Nenhuma matrícula disponível. O acesso depende de convite e verificação do vínculo.
          </p><article :for={{id, enrollment} <- @streams.enrollments} id={id} class="card">
            <h2>{enrollment.values["student_name"] || "Matrícula em preenchimento"}</h2><p>
              {enrollment.status}
            </p><.link
              id={"open-enrollment-#{enrollment.id}"}
              patch={~p"/o/#{@current_scope.organization.slug}/matriculas/#{enrollment.id}"}
            >Acompanhar matrícula</.link>
          </article>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
