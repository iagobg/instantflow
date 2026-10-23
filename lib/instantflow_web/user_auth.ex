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
            case Identity.scope_for_token(session["user_token"], scope.organization_id) do
              nil ->
                {:halt, Phoenix.LiveView.redirect(socket, to: "/organizacoes")}

              fresh ->
                if(
                  socket.view in [
                    InstantflowWeb.TemplateLive,
                    InstantflowWeb.TemplatesLive
                  ] and
                    fresh.role != "admin",
                  do:
                    {:halt,
                     Phoenix.LiveView.redirect(socket, to: "/o/#{fresh.organization.slug}")},
                  else:
                    {:cont,
                     socket
                     |> Phoenix.Component.assign(:current_scope, fresh)
                     |> Phoenix.Component.assign(
                       :workspace_navigation,
                       Instantflow.WorkflowCatalog.Workspaces.navigation(fresh)
                     )}
                )
            end
          end)
        end

        socket =
          socket
          |> Phoenix.LiveView.put_private(:validate_scope, validate)
          |> Phoenix.Component.assign(:current_scope, scope)
          |> Phoenix.Component.assign(
            :workspace_navigation,
            Instantflow.WorkflowCatalog.Workspaces.navigation(scope)
          )
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
              case validate.(socket) do
                {:halt, socket} ->
                  {:halt, socket}

                {:cont, socket} ->
                  if socket.view in [
                       InstantflowWeb.ProcessesLive,
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
                   InstantflowWeb.ProcessesLive
                 ],
                 do: send(self(), :reconcile)

              case validate.(socket) do
                {:halt, socket} -> {:halt, socket}
                {:cont, socket} -> {:halt, socket}
              end

            :permissions_changed, socket ->
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
                       InstantflowWeb.ProcessesLive
                     ],
                     do: {:cont, socket},
                     else: {:halt, socket}
              end

            _, socket ->
              validate.(socket)
          end)

        {:cont, socket}
    end
  end
end
