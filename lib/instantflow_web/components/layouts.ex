defmodule InstantflowWeb.Layouts do
  use InstantflowWeb, :html
  embed_templates "layouts/*"
  attr :flash, :map, required: true
  attr :current_scope, :any, default: nil
  attr :unsaved, :boolean, default: false
  slot :inner_block, required: true

  def app(assigns) do
    assigns =
      assign(
        assigns,
        :navigation,
        if(assigns.current_scope,
          do: Instantflow.WorkflowCatalog.Workspaces.navigation(assigns.current_scope)
        )
      )

    ~H"""
    <a href="#main-content" class="skip-link">Pular para o conteúdo</a>
    <div class={if @current_scope, do: "app-shell", else: "auth-shell"}>
      <aside :if={@current_scope} class="sidebar">
        <.link
          navigate={~p"/o/#{@current_scope.organization.slug}"}
          class="brand"
          aria-label="InstantFlow, início"
        ><.logo /></.link>
        <div class="organization-label">
          <span class="org-avatar">{@current_scope.organization.name
          |> String.split()
          |> Enum.take(2)
          |> Enum.map_join(&String.first/1)}</span><div>
            <strong>{@current_scope.organization.name}</strong><small>Espaço da organização</small>
          </div>
        </div>
        <p class="nav-label">ESPAÇO DE TRABALHO</p>
        <.link
          id="switch-organization"
          href={~p"/organizacoes"}
          class="nav-link"
          data-confirm={
            if @unsaved,
              do: "Há alterações não salvas. Deseja descartá-las e selecionar outra organização?"
          }
        >Trocar organização</.link>
        <nav aria-label="Navegação principal">
          <.link
            id="processes-link"
            navigate={~p"/o/#{@current_scope.organization.slug}/processos"}
            class="nav-link"
          ><.icon name="hero-squares-2x2" />Processos</.link>
          <.link
            :for={process <- @navigation}
            id={"process-link-#{process.id}"}
            navigate={~p"/o/#{@current_scope.organization.slug}/processos/#{process.id}"}
            class="nav-link"
          ><.icon name="hero-squares-2x2" />{process.label}</.link>
          <.link
            :if={@current_scope.role == "admin"}
            id="workflow-templates-link"
            navigate={~p"/o/#{@current_scope.organization.slug}/modelos"}
            class="nav-link"
          ><.icon name="hero-share" />Modelos de fluxo</.link>
          <.link
            :if={
              Instantflow.Access.role?(
                @current_scope,
                ~w(python_author python_reviewer python_binder python_source)
              )
            }
            id="calculations-link"
            navigate={~p"/o/#{@current_scope.organization.slug}/calculos"}
            class="nav-link"
          ><.icon name="hero-squares-2x2" />Cálculos Python</.link>

          <.link navigate={~p"/o/#{@current_scope.organization.slug}"} class="nav-link"><.icon name="hero-squares-2x2" />Visão geral</.link><.link
            :if={@current_scope.role == "admin"}
            navigate={~p"/o/#{@current_scope.organization.slug}/equipe"}
            class="nav-link"
          ><.icon name="hero-users" />Equipe e convites</.link>
        </nav>
        <div class="sidebar-foot">
          <span class="badge sim">◇ Demonstração</span><p>
            Dados fictícios.<br />Integrações simuladas.
          </p>
        </div>
      </aside>
      <div class="workspace">
        <header class="topbar">
          <span>{if @current_scope,
            do: @current_scope.department.name,
            else: "Sua organização, em fluxo"}</span><div class="topbar-actions">
            <button
              id="theme-toggle"
              type="button"
              class="icon-button"
              aria-label="Alternar tema claro ou escuro"
            ><.icon name="hero-moon" /></button><span :if={@current_scope} class="user-name">{@current_scope.user.name}</span><.link
              :if={@current_scope}
              href={~p"/sair"}
              method="delete"
              class="icon-button"
              aria-label="Sair da conta"
            ><.icon name="hero-arrow-right-on-rectangle" /></.link>
          </div>
        </header>
        <main id="main-content" tabindex="-1">
          <div class="demo-banner">
            <span>◇</span> Ambiente de demonstração · Dados fictícios e integrações simuladas
          </div><.flash_group flash={@flash} />{render_slot(@inner_block)}
        </main>
        <footer>InstantFlow <span>Clareza em cada etapa.</span></footer>
      </div>
    </div>
    """
  end

  def logo(assigns) do
    ~H"""
    <img
      class="logo-light"
      src={~p"/images/instantflow-logo-light.svg"}
      alt="InstantFlow"
      width="180"
      height="48"
    /><img
      class="logo-dark"
      src={~p"/images/instantflow-logo-dark.svg"}
      alt="InstantFlow"
      width="180"
      height="48"
    />
    """
  end

  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <div id="flash-group" aria-live="polite">
      <p
        :if={message = Phoenix.Flash.get(@flash, :info)}
        id="flash-info"
        role="status"
        class="flash info"
      >
        {message}
      </p><p
        :if={message = Phoenix.Flash.get(@flash, :error)}
        id="flash-error"
        role="alert"
        class="flash error"
      >
        {message}
      </p><p
        id="connection-error"
        class="flash error"
        hidden
        phx-disconnected={JS.remove_attribute("hidden", to: "#connection-error")}
        phx-connected={JS.set_attribute({"hidden", ""}, to: "#connection-error")}
      >
        Conexão interrompida. Tentando reconectar…
      </p>
    </div>
    """
  end
end
