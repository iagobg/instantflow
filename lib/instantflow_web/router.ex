defmodule InstantflowWeb.Router do
  use InstantflowWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {InstantflowWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug InstantflowWeb.UserAuth, :fetch_scope
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", InstantflowWeb do
    pipe_through :browser

    get "/entrar", SessionController, :new
    post "/entrar", SessionController, :create
    delete "/sair", SessionController, :delete
    get "/convite", SessionController, :invitation
    post "/convite", SessionController, :accept
  end

  pipeline :authenticated do
    plug InstantflowWeb.UserAuth, :require_authenticated
  end

  pipeline :organization do
    plug InstantflowWeb.UserAuth, :require_organization
  end

  scope "/", InstantflowWeb do
    pipe_through [:browser, :authenticated]

    get "/", OrganizationController, :home
    get "/organizacoes", OrganizationController, :index
  end

  scope "/o/:organization_slug", InstantflowWeb do
    pipe_through [:browser, :authenticated, :organization]

    get "/documentos/:key", DocumentController, :download

    live_session :internal, on_mount: [{InstantflowWeb.UserAuth, :authenticated}] do
      live "/", HomeLive, :index
      live "/processos", ProcessesLive, :index
      live "/processos/:workflow_id/comunicacoes", MessagesLive, :index
      live "/processos/:workflow_id/participacao/:page_key", ParticipantLive, :index
      live "/processos/:workflow_id/participacao/:page_key/registros/:id", ParticipantLive, :show
      live "/processos/:workflow_id/fluxo", FlowLive, :index
      live "/processos/:workflow_id/registros/:id/fluxo", FlowLive, :show
      live "/processos/:workflow_id", ProcessLive, :index
      live "/processos/:workflow_id/p/:page_key", ProcessLive, :index
      live "/processos/:workflow_id/p/:page_key/atendimentos/:id", ProcessLive, :show
      live "/processos/:workflow_id/registros/:id", RequestLive, :show
      live "/equipe", TeamLive, :index
      live "/modelos", TemplatesLive, :index
      live "/modelos/:id", TemplateLive, :show
      live "/calculos", CalculationsLive, :index
      live "/solicitacoes", RequestsLive, :index
      live "/solicitacoes/:id", RequestLive, :show
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", InstantflowWeb do
  #   pipe_through :api
  # end
end
