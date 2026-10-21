defmodule InstantflowWeb.TemplatesLive do
  use InstantflowWeb, :live_view
  alias Instantflow.{Identity, WorkflowCatalog.Templates}

  def mount(_, _, socket) do
    if Identity.admin?(socket.assigns.current_scope) do
      {:ok,
       socket
       |> assign(
         page_title: "Modelos de fluxo",
         export: nil,
         new_form: to_form(%{}, as: :workflow),
         import_form: to_form(%{}, as: :import)
       )
       |> allow_upload(:template, accept: ~w(.json), max_entries: 1, max_file_size: 1_048_576)
       |> refresh()}
    else
      {:ok, denied(socket)}
    end
  end

  def handle_event("new", %{"workflow" => p}, socket) do
    open_result(socket, Templates.new(socket.assigns.current_scope, p["key"], p["name"]))
  end

  def handle_event("clone", %{"id" => id}, socket) do
    open_result(socket, Templates.clone(socket.assigns.current_scope, integer(id)))
  end

  def handle_event("validate-upload", _, socket), do: {:noreply, socket}

  def handle_event("import", %{"import" => p}, socket) do
    files =
      consume_uploaded_entries(socket, :template, fn %{path: path}, _ ->
        {:ok, File.read!(path)}
      end)

    json = List.first(files) || p["json"] || ""
    target = if p["workflow_id"] in [nil, ""], do: nil, else: integer(p["workflow_id"])

    open_result(
      socket,
      Templates.import(socket.assigns.current_scope, json, %{
        "workflow_id" => target,
        "template_key" => p["key"]
      })
    )
  end

  def handle_event("export", %{"id" => id}, socket) do
    case Templates.export(socket.assigns.current_scope, :version, integer(id)) do
      {:ok, exported} -> {:noreply, assign(socket, export: exported)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, message(reason))}
    end
  end

  defp open_result(socket, {:ok, draft}),
    do:
      {:noreply,
       push_navigate(socket,
         to: ~p"/o/#{socket.assigns.current_scope.organization.slug}/modelos/#{draft.id}"
       )}

  defp open_result(socket, {:error, reason}),
    do: {:noreply, put_flash(socket, :error, message(reason))}

  defp refresh(socket) do
    case Templates.list(socket.assigns.current_scope) do
      {:ok, data} ->
        socket
        |> assign(targets: Enum.map(data.workflows, &{&1.name <> " · " <> &1.key, &1.id}))
        |> stream(:drafts, data.drafts, reset: true)
        |> stream(:versions, data.versions, reset: true)

      _ ->
        denied(socket)
    end
  end

  defp denied(socket),
    do:
      socket
      |> put_flash(:error, "Apenas administradores podem gerenciar modelos.")
      |> push_navigate(to: ~p"/o/#{socket.assigns.current_scope.organization.slug}")

  def integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 and id < 9_223_372_036_854_775_807 -> id
      _ -> -1
    end
  end

  def integer(_), do: -1

  def message({:invalid_definition, errors}), do: Enum.join(errors, " ")

  def message(:invalid_json),
    do: "JSON inválido, com chaves duplicadas ou acima dos limites de 1 MiB e 20 níveis."

  def message(:unsupported_format), do: "Versão de formato não suportada. Use format_version 1.0."

  def message(:key_taken),
    do:
      "Esta chave já existe. Escolha outra chave ou selecione explicitamente o modelo de destino."

  def message(:key_mismatch), do: "A chave deve corresponder ao modelo de destino."

  def message(:conflict),
    do:
      "Outra pessoa alterou este rascunho ou publicou uma nova versão. Compare as alterações antes de continuar."

  def message(:invalid_bindings),
    do: "Mapeamento inválido. Use somente perfis e departamentos desta organização."

  def message(:already_published),
    do: "Este rascunho já foi publicado. Clone a versão para continuar."

  def message(:forbidden), do: "Seu perfil não permite gerenciar modelos nesta organização."

  def message(:immutable_key),
    do: "A chave é estável. Crie outro item para usar uma chave diferente."

  def message(:duplicate_key), do: "Esta chave já existe. Escolha outra chave."
  def message(_), do: "Não foi possível concluir a ação. Confira os campos e as referências."

  def role_label(role),
    do:
      Map.get(
        %{
          "admin" => "Administrador",
          "staff" => "Colaborador",
          "teacher" => "Professor",
          "admissions" => "Admissões",
          "head" => "Coordenação",
          "finance" => "Financeiro",
          "finance_allocator" => "Alocação financeira",
          "finance_reverser" => "Estorno financeiro",
          "operations" => "Operações",
          "it" => "TI",
          "dean" => "Direção",
          "counselor" => "Orientação"
        },
        role,
        role
      )

  defp upload_message(:too_large), do: "O arquivo excede 1 MiB."
  defp upload_message(:too_many_files), do: "Selecione apenas um arquivo."
  defp upload_message(:not_accepted), do: "Selecione um arquivo .json."
  defp upload_message(_), do: "Não foi possível carregar o arquivo."

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="page-heading">
        <div>
          <p class="eyebrow">ADMINISTRAÇÃO</p><h1>Modelos de fluxo</h1><p>
            Prepare, revise e publique os processos da organização.
          </p>
        </div>
      </div>
      <div class="template-grid">
        <section class="card">
          <h2>Criar um processo</h2>
          <.form for={@new_form} id="new-workflow-form" phx-submit="new">
            <.input
              field={@new_form[:key]}
              label="Chave do modelo"
              required
              pattern="[a-z][a-z0-9_]{0,63}"
              maxlength="64"
            />
            <.input field={@new_form[:name]} label="Nome" required maxlength="200" />
            <button id="new-workflow" class="btn primary" phx-disable-with="Criando…">Criar rascunho</button>
          </.form>
        </section>
        <section class="card">
          <h2>Importar modelo JSON</h2><p>
            Somente a definição será importada. Mapeamentos locais precisam de revisão; a publicação é uma ação separada.
          </p>
          <.form
            for={@import_form}
            id="import-template-form"
            phx-submit="import"
            phx-change="validate-upload"
          >
            <.input
              field={@import_form[:workflow_id]}
              type="select"
              label="Destino"
              options={@targets}
              prompt="Criar um modelo independente"
            />
            <.input
              field={@import_form[:key]}
              label="Nova chave (opcional, apenas para novo modelo)"
              pattern="[a-z][a-z0-9_]{0,63}"
              maxlength="64"
            />
            <label for={@uploads.template.ref}>Arquivo JSON (até 1 MiB)</label><.live_file_input upload={
              @uploads.template
            } />
            <p :for={error <- upload_errors(@uploads.template)} role="alert">
              {upload_message(error)}
            </p>
            <div :for={entry <- @uploads.template.entries} id={"upload-#{entry.ref}"}>
              <p>{entry.client_name} · {entry.progress}%</p><p
                :for={error <- upload_errors(@uploads.template, entry)}
                role="alert"
              >
                {upload_message(error)}
              </p>
            </div>
            <.input
              field={@import_form[:json]}
              type="textarea"
              label="Ou cole o JSON"
              maxlength="1048576"
            />
            <button id="import-template" class="btn primary" phx-disable-with="Validando…">Validar e criar rascunho</button>
          </.form>
        </section>
      </div>
      <section class="card template-section">
        <h2>Rascunhos</h2><div id="template-drafts" phx-update="stream">
          <p id="template-drafts-empty" class="empty-state">Nenhum rascunho nesta organização.</p>
          <article :for={{id, draft} <- @streams.drafts} id={id} class="request-row">
            <div>
              <strong>{draft.definition["name"]}</strong><small>Revisão {draft.revision} · {if draft.published_version_id,
                do: "Publicado",
                else: "Em preparação"}</small>
            </div><.link
              id={"open-draft-#{draft.id}"}
              navigate={~p"/o/#{@current_scope.organization.slug}/modelos/#{draft.id}"}
              class="btn"
            >Abrir</.link>
          </article>
        </div>
      </section>
      <section class="card template-section">
        <h2>Últimas versões publicadas</h2><p>
          Clonar cria um rascunho independente da versão em uso.
        </p><div id="template-versions" phx-update="stream">
          <p id="template-versions-empty" class="empty-state">Nenhuma versão publicada.</p>
          <article :for={{id, version} <- @streams.versions} id={id} class="request-row">
            <div>
              <strong>{version.definition["name"]}</strong><small>Versão {version.number}</small>
            </div><button
              id={"clone-version-#{version.id}"}
              class="btn"
              phx-click="clone"
              phx-value-id={version.id}
            >Clonar para editar</button><button
              id={"export-version-#{version.id}"}
              class="btn"
              phx-click="export"
              phx-value-id={version.id}
            >Revisar exportação</button>
          </article>
        </div>
      </section>
      <section :if={@export} id="export-preview" class="card template-section">
        <h2>Revisão da exportação</h2><p>
          {@export.status}. Somente estrutura, rótulos e regras; sem mapeamentos locais, pessoas ou solicitações.
        </p><p>O conteúdo pode revelar práticas da organização. Revise antes de compartilhar.</p><p>
          SHA-256: <code>{@export.digest}</code>
        </p><pre id="export-json">{@export.json}</pre><a
          id="download-template"
          class="btn primary"
          href={"data:application/json;charset=utf-8," <> URI.encode(@export.json, &URI.char_unreserved?/1)}
          download="modelo-publicado.json"
        >Baixar JSON revisado</a>
      </section>
    </Layouts.app>
    """
  end
end
