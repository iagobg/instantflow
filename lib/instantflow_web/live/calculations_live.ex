defmodule InstantflowWeb.CalculationsLive do
  use InstantflowWeb, :live_view
  alias Instantflow.Calculations.Catalogue
  alias Instantflow.WorkflowCatalog.Interchange
  alias InstantflowWeb.RuntimeErrors

  def mount(_, _, socket) do
    socket =
      socket
      |> assign(
        page_title: "Cálculos Python",
        form: to_form(%{}, as: :script),
        source_text: nil,
        workflow_json: nil,
        verifying: false
      )
      |> allow_upload(:script_file, accept: ~w(.py), max_entries: 1, max_file_size: 32_768)

    case Catalogue.list(socket.assigns.current_scope) do
      {:ok, scripts} ->
        {:ok, stream(socket, :scripts, scripts)}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/o/#{socket.assigns.current_scope.organization.slug}")}
    end
  end

  def handle_event("example", _, socket) do
    attrs = Instantflow.Calculations.Demo.attributes(socket.assigns.form[:runtime].value || "")

    params =
      Map.new(attrs, fn {key, value} ->
        {key,
         if(key in ~w(input_schema output_schema fixtures allowed_roles),
           do: Jason.encode!(value, pretty: true),
           else: value
         )}
      end)

    {:noreply, assign(socket, form: to_form(params, as: :script))}
  end

  def handle_event("validate", %{"script" => params}, socket),
    do: {:noreply, assign(socket, form: to_form(params, as: :script))}

  def handle_event("register", %{"script" => params}, socket) do
    files =
      consume_uploaded_entries(socket, :script_file, fn %{path: path}, _ ->
        {:ok, File.read!(path)}
      end)

    source =
      case files do
        [source] -> source
        _ -> params["source"]
      end

    with {:ok, input} <- Interchange.decode(params["input_schema"] || ""),
         {:ok, output} <- Interchange.decode(params["output_schema"] || ""),
         {:ok, fixtures} <- Interchange.decode(params["fixtures"] || ""),
         {:ok, roles} <- Interchange.decode(params["allowed_roles"] || ""),
         {:ok, _} <-
           Catalogue.register(socket.assigns.current_scope, %{
             "key" => params["key"],
             "runtime" => params["runtime"],
             "source" => source,
             "input_schema" => input,
             "output_schema" => output,
             "fixtures" => fixtures,
             "allowed_roles" => roles
           }) do
      reload(
        put_flash(
          socket,
          :info,
          "Versão imutável registrada. Revise o código e verifique os exemplos antes de ativar."
        )
      )
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, RuntimeErrors.message(reason))}
    end
  end

  def handle_event("verify", %{"id" => id}, socket) do
    with false <- socket.assigns.verifying,
         {id, ""} <- Integer.parse(id) do
      actor = socket.assigns.current_scope

      {:noreply,
       socket
       |> assign(verifying: true)
       |> start_async(:verify, fn -> Catalogue.verify(actor, id) end)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("activation", %{"id" => id, "enabled" => enabled}, socket) do
    with {id, ""} <- Integer.parse(id),
         true <- enabled in ~w(true false),
         {:ok, _} <- Catalogue.activate(socket.assigns.current_scope, id, enabled == "true") do
      reload(
        put_flash(
          socket,
          :info,
          "Ativação atualizada. Resultados de versões desativadas serão recusados."
        )
      )
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, RuntimeErrors.message(reason))}
      _ -> {:noreply, put_flash(socket, :error, RuntimeErrors.message(:forbidden))}
    end
  end

  def handle_event("workflow-example", %{"id" => id}, socket) do
    with true <- Instantflow.Access.role?(socket.assigns.current_scope, ["python_binder"]),
         {:ok, scripts} <- Catalogue.list(socket.assigns.current_scope),
         script when not is_nil(script) <- Enum.find(scripts, &(to_string(&1.id) == id)) do
      definition = Instantflow.Calculations.Demo.definition(script.key, script.digest)
      {:noreply, assign(socket, workflow_json: Interchange.encode(definition))}
    else
      _ -> {:noreply, put_flash(socket, :error, RuntimeErrors.message(:forbidden))}
    end
  end

  def handle_event("source", %{"id" => id}, socket) do
    with {id, ""} <- Integer.parse(id),
         {:ok, script} <- Catalogue.source(socket.assigns.current_scope, id) do
      {:noreply, assign(socket, source_text: script.source)}
    else
      _ -> {:noreply, put_flash(socket, :error, RuntimeErrors.message(:forbidden))}
    end
  end

  def handle_async(:verify, result, socket) do
    socket = assign(socket, verifying: false)

    case result do
      {:ok, {:ok, _}} ->
        reload(
          put_flash(
            socket,
            :info,
            "Exemplos sintéticos verificados. A ativação exige revisão explícita."
          )
        )

      _ ->
        reload(put_flash(socket, :error, RuntimeErrors.message(:fixture_failed)))
    end
  end

  def handle_info(:reconcile, socket), do: reload(assign(socket, source_text: nil))
  def handle_info(:permissions_changed, socket), do: reload(assign(socket, source_text: nil))

  defp reload(socket) do
    case Catalogue.list(socket.assigns.current_scope) do
      {:ok, scripts} ->
        {:noreply, socket |> assign(source_text: nil) |> stream(:scripts, scripts, reset: true)}

      _ ->
        {:noreply,
         socket
         |> assign(source_text: nil)
         |> push_navigate(to: ~p"/o/#{socket.assigns.current_scope.organization.slug}")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="page-heading">
        <h1>Cálculos Python</h1><p>Demonstração universitária · somente dados sintéticos</p>
      </div>
      <section class="card">
        <p>Execução desativada por padrão. Registrar ou importar um fluxo não ativa código.
          O operador deve validar o executor gVisor antes de habilitar cálculos.</p>
        <button
          :if={Instantflow.Access.role?(@current_scope, ["python_author"])}
          id="load-trip-example"
          class="btn"
          phx-click="example"
        >Carregar exemplo de passeio</button>
        <.form
          :if={Instantflow.Access.role?(@current_scope, ["python_author"])}
          for={@form}
          id="script-form"
          phx-change="validate"
          phx-submit="register"
        >
          <.input field={@form[:key]} label="Referência do cálculo" required maxlength="64" />
          <.input
            field={@form[:runtime]}
            label="Digest SHA-256 da imagem Python aprovada (64 caracteres)"
            required
            maxlength="64"
          />
          <label for={@uploads.script_file.ref}>Enviar código Python (.py, até 32 KiB)</label>
          <.live_file_input upload={@uploads.script_file} />
          <p :for={_error <- upload_errors(@uploads.script_file)}>
            Arquivo recusado. Envie um arquivo .py de até 32 KiB.
          </p>
          <.input
            field={@form[:source]}
            type="textarea"
            label="Ou cole o código Python: def calculate(inputs)"
            maxlength="32768"
          />
          <.input
            field={@form[:input_schema]}
            type="textarea"
            label="Esquema de entrada (JSON: nome → type, min, max)"
            required
          />
          <.input
            field={@form[:output_schema]}
            type="textarea"
            label="Esquema de saída (JSON: nome → type, min, max)"
            required
          />
          <.input
            field={@form[:fixtures]}
            type="textarea"
            label="Exemplos sintéticos (JSON: lista de input/output)"
            required
          />
          <.input
            field={@form[:allowed_roles]}
            label="Perfis locais autorizados (lista JSON)"
            required
          />
          <button id="register-script" class="btn primary" phx-disable-with="Registrando…">Registrar nova versão</button>
        </.form>
      </section>
      <p :if={@workflow_json}>
        Importe este JSON em Modelos de fluxo e configure os papéis e o departamento locais. O exemplo exige os campos e saídas do cálculo de passeio.
      </p>
      <pre :if={@workflow_json} id="calculation-workflow-json" class="card">{@workflow_json}</pre>
      <pre :if={@source_text} id="script-source" class="card">{@source_text}</pre>
      <div id="scripts" phx-update="stream">
        <article :for={{id, script} <- @streams.scripts} id={id} class="card">
          <h2>{script.key}</h2><p>Referência imutável: {script.digest}</p>
          <button
            :if={Instantflow.Access.role?(@current_scope, ["python_binder"])}
            id={"workflow-example-#{script.id}"}
            class="btn"
            phx-click="workflow-example"
            phx-value-id={script.id}
          >Gerar fluxo do exemplo de passeio</button>
          <p>
            {if script.enabled, do: "Ativo", else: "Desativado"} · {if script.verified,
              do: "Exemplos verificados",
              else: "Aguardando verificação"}
          </p>
          <button
            :if={Instantflow.Access.role?(@current_scope, ["python_source"])}
            id={"source-script-#{script.id}"}
            phx-click="source"
            phx-value-id={script.id}
            class="btn"
          >Revisar código</button>
          <button
            :if={Instantflow.Access.role?(@current_scope, ["python_reviewer"])}
            id={"verify-script-#{script.id}"}
            phx-click="verify"
            phx-value-id={script.id}
            disabled={@verifying}
            class="btn"
          >Verificar exemplos</button>
          <button
            :if={
              not script.enabled and script.verified and
                Instantflow.Access.role?(@current_scope, ["python_reviewer"])
            }
            id={"activate-script-#{script.id}"}
            phx-click="activation"
            phx-value-id={script.id}
            phx-value-enabled="true"
            class="btn"
          >Ativar versão revisada</button>
          <button
            :if={script.enabled and Instantflow.Access.role?(@current_scope, ["python_reviewer"])}
            id={"disable-script-#{script.id}"}
            phx-click="activation"
            phx-value-id={script.id}
            phx-value-enabled="false"
            class="btn"
          >Desativar versão</button>
        </article>
      </div>
    </Layouts.app>
    """
  end
end
