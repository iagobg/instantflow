defmodule InstantflowWeb.UserAuth do
  import Plug.Conn
  import Phoenix.Controller
  alias Instantflow.{Identity, Organizations}
  def init(action), do: action
  def call(conn, action), do: apply(__MODULE__, action, [conn, []])

  def fetch_scope(conn, _) do
    user = Identity.user_for_token(get_session(conn, :user_token))
    scope = Organizations.scope(user, conn.path_params["organization_slug"])
    conn |> assign(:current_user, user) |> assign(:current_scope, scope)
  end

  def require_authenticated(conn, _) do
    if conn.assigns.current_user,
      do: conn,
      else:
        conn
        |> put_flash(:error, "Entre para acessar o ambiente interno.")
        |> redirect(to: "/entrar")
        |> halt()
  end

  def require_organization(conn, _) do
    if conn.assigns.current_scope,
      do: conn,
      else:
        conn
        |> put_flash(:error, "Organização indisponível ou sem acesso.")
        |> redirect(to: "/organizacoes")
        |> halt()
  end

  def on_mount(:authenticated, params, session, socket) do
    Instantflow.Tenant.with_connection(fn -> mount_authenticated(params, session, socket) end)
  end

  @doc "Validate the current session and run a composite parameter read in one connection lease."
  def with_validated_scope(socket, fun) do
    Instantflow.Tenant.with_connection(fn ->
      case socket.private.validate_scope.(socket) do
        {:cont, fresh} -> fun.(fresh)
        {:halt, stopped} -> {:noreply, stopped}
      end
    end)
  end

  defp mount_authenticated(params, session, socket) do
    user = Identity.user_for_token(session["user_token"])
    slug = params["organization_slug"]

    case Organizations.scope(user, slug) do
      nil ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/organizacoes")}

      scope ->
        if Phoenix.LiveView.connected?(socket) do
          Phoenix.PubSub.subscribe(Instantflow.PubSub, "organization:#{scope.organization_id}")

          Phoenix.PubSub.subscribe(
            Instantflow.PubSub,
            "organization:#{scope.organization_id}:user:#{scope.user_id}"
          )

          Process.send_after(self(), :revalidate_organization, 30000)
        end

        validate = fn socket ->
          Instantflow.Tenant.with_connection(fn ->
            case Identity.read_session(session["user_token"], scope, fn context ->
                   fresh = Instantflow.Tenant.context_scope!(context)
                   fresh = Instantflow.Repo.preload(fresh, :department)

                   {fresh, assign_navigation(socket, context)}
                 end) do
              {:error, _} ->
                {:halt, Phoenix.LiveView.redirect(socket, to: "/organizacoes")}

              {:ok, {fresh, socket}} ->
                if(
                  socket.view in [
                    InstantflowWeb.TemplateLive,
                    InstantflowWeb.TemplatesLive
                  ] and
                    fresh.role != "admin",
                  do:
                    {:halt,
                     Phoenix.LiveView.redirect(socket, to: "/o/#{fresh.organization.slug}")},
                  else: {:cont, Phoenix.Component.assign(socket, :current_scope, fresh)}
                )
            end
          end)
        end

        socket = Phoenix.Component.assign(socket, :workspace_navigation, [])
        socket = Instantflow.Tenant.read_context(scope, &assign_navigation(socket, &1), socket)

        socket =
          socket
          |> Phoenix.LiveView.put_private(:validate_scope, validate)
          |> Phoenix.Component.assign(:current_scope, scope)
          |> Phoenix.LiveView.attach_hook(:validate_session, :handle_event, fn _, _, socket ->
            validate.(socket)
          end)
          |> Phoenix.LiveView.attach_hook(:tenant_params, :handle_params, fn params, _, socket ->
            cond do
              params["organization_slug"] != slug ->
                {:halt, Phoenix.LiveView.redirect(socket, to: "/organizacoes")}

              socket.view == InstantflowWeb.ProcessLive ->
                # ProcessLive validates inside the same connection lease as its
                # composite projection, avoiding another pool wait between them.
                {:cont, socket}

              true ->
                validate.(socket)
            end
          end)
          |> Phoenix.LiveView.attach_hook(:tenant_lifecycle, :handle_info, fn
            :workspaces_changed, socket ->
              InstantflowWeb.RefreshNotifications.coalesce(socket, :workspaces_changed)

              case validate.(invalidate_navigation(socket)) do
                {:halt, socket} ->
                  {:halt, socket}

                {:cont, socket} ->
                  if socket.view in [
                       InstantflowWeb.ProcessesLive,
                       InstantflowWeb.FlowLive,
                       InstantflowWeb.ProcessLive,
                       InstantflowWeb.RequestsLive
                     ], do: {:cont, socket}, else: {:halt, socket}
              end

            :access_revoked, socket ->
              case validate.(socket) do
                {:halt, socket} -> {:halt, socket}
                {:cont, socket} -> {:halt, socket}
              end

            :revalidate_organization, socket ->
              Process.send_after(self(), :revalidate_organization, 30000)

              if socket.view in [
                   InstantflowWeb.RequestLive,
                   InstantflowWeb.ParticipantLive,
                   InstantflowWeb.MessagesLive,
                   InstantflowWeb.RequestsLive,
                   InstantflowWeb.CalculationsLive,
                   InstantflowWeb.ProcessLive,
                   InstantflowWeb.ProcessesLive,
                   InstantflowWeb.FlowLive
                 ],
                 do: send(self(), :reconcile)

              case validate.(invalidate_navigation(socket)) do
                {:halt, socket} -> {:halt, socket}
                {:cont, socket} -> {:halt, socket}
              end

            :permissions_changed, socket ->
              InstantflowWeb.RefreshNotifications.coalesce(socket, :permissions_changed)

              case validate.(socket) do
                {:halt, socket} ->
                  {:halt, socket}

                {:cont, socket} ->
                  if socket.view in [
                       InstantflowWeb.RequestLive,
                       InstantflowWeb.ParticipantLive,
                       InstantflowWeb.MessagesLive,
                       InstantflowWeb.RequestsLive,
                       InstantflowWeb.CalculationsLive,
                       InstantflowWeb.ProcessLive,
                       InstantflowWeb.ProcessesLive,
                       InstantflowWeb.FlowLive
                     ],
                     do: {:cont, socket},
                     else: {:halt, socket}
              end

            message, socket ->
              InstantflowWeb.RefreshNotifications.coalesce(socket, message)
              validate.(socket)
          end)

        {:cont, socket}
    end
  end

  # This key only controls a bounded presentation projection. Every callback
  # still proves its session and loads current membership/grants before comparing.
  # The generation arrives in the existing organization read, without another SQL call.
  defp assign_navigation(socket, context) do
    scope = Instantflow.Tenant.context_scope!(context)
    key = {Instantflow.Access.fingerprint(scope), scope.organization.catalog_generation}

    if socket.private[:workspace_navigation_key] == key do
      socket
    else
      socket
      |> Phoenix.Component.assign(
        :workspace_navigation,
        Instantflow.WorkflowCatalog.Workspaces.navigation_in_context(context)
      )
      |> Phoenix.LiveView.put_private(:workspace_navigation_key, key)
    end
  end

  defp invalidate_navigation(socket),
    do: Phoenix.LiveView.put_private(socket, :workspace_navigation_key, nil)
end
