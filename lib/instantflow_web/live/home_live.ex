defmodule InstantflowWeb.HomeLive do
  use InstantflowWeb, :live_view

  def mount(_params, _session, %{assigns: %{current_scope: %{role: "parent"}}} = socket),
    do:
      {:ok,
       push_navigate(socket,
         to: ~p"/o/#{socket.assigns.current_scope.organization.slug}/matriculas"
       )}

  def mount(_params, _session, socket), do: {:ok, assign(socket, :page_title, "Visão geral")}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="page-heading">
        <div>
          <p class="eyebrow">SEU ESPAÇO DE TRABALHO</p><h1>Visão geral</h1><p>
            Olá, {@current_scope.user.name}. Tudo começa com uma equipe conectada.
          </p>
        </div><span class="badge">✓ Ambiente disponível</span>
      </div>
      <section class="welcome-panel" aria-labelledby="welcome-title">
        <div>
          <span class="badge sim">◇ Ambiente de demonstração</span><h2 id="welcome-title">
            Menos caminhos soltos.<br />Mais trabalho em fluxo.
          </h2><p>
            Um lugar para organizar solicitações, conectar departamentos e acompanhar cada decisão da sua organização.
          </p><.link
            :if={@current_scope.role == "admin"}
            navigate={~p"/o/#{@current_scope.organization.slug}/equipe"}
            class="btn primary"
          >Organizar equipe <.icon name="hero-arrow-right" /></.link>
        </div>
        <div class="flow-illustration" aria-hidden="true">
          <span>01 · Solicitar</span><i></i><span>02 · Colaborar</span><i></i><span>03 · Concluir</span>
        </div>
      </section>
      <div class="foundation-grid">
        <section class="card">
          <.icon name="hero-building-office" /><p class="eyebrow">ORGANIZAÇÃO</p><h2>
            {@current_scope.organization.name}
          </h2><p>Seus processos, pessoas e responsabilidades em um ambiente compartilhado.</p><span class="badge">✓ Organização configurada</span>
        </section>
        <section class="card">
          <.icon name="hero-users" /><p class="eyebrow">SEU DEPARTAMENTO</p><h2>
            {@current_scope.department.name}
          </h2><p>
            Seu perfil: {if @current_scope.role == "admin", do: "Administrador", else: "Colaborador"}.
          </p><span class="badge">✓ Acesso por convite</span>
        </section>
        <section class="card">
          <.icon name="hero-squares-2x2" /><p class="eyebrow">TRABALHO EM FLUXO</p><h2>
            Fluxos de trabalho
          </h2><p>
            Abra os processos configurados pela organização e acompanhe seus atendimentos e registros.
          </p><.link navigate={~p"/o/#{@current_scope.organization.slug}/processos"} class="badge">→ Abrir processos</.link>
        </section>
      </div>
      <section class="note">
        <.icon name="hero-information-circle" /><div>
          <strong>Uma base pronta para crescer</strong><p>
            Crie processos a partir de uma estrutura inicial ou adapte um exemplo. Somente os modelos publicados entram no seu espaço de trabalho.
          </p>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
