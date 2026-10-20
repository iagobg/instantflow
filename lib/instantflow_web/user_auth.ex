defmodule InstantflowWeb.UserAuth do
  import Plug.Conn
  import Phoenix.Controller
  alias Instantflow.Identity
  def init(action), do: action
  def call(conn, action), do: apply(__MODULE__, action, [conn, []])

  def fetch_scope(conn, _opts),
    do: assign(conn, :current_scope, Identity.scope_for_token(get_session(conn, :user_token)))

  def require_authenticated(conn, _opts) do
    if conn.assigns.current_scope do
      conn
    else
      conn
      |> put_flash(:error, "Entre para acessar o ambiente interno.")
      |> redirect(to: "/entrar")
      |> halt()
    end
  end

  def on_mount(:authenticated, _params, session, socket) do
    case Identity.scope_for_token(session["user_token"]) do
      nil ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/entrar")}

      scope ->
        socket =
          socket
          |> Phoenix.Component.assign(:current_scope, scope)
          |> Phoenix.LiveView.attach_hook(:validate_session, :handle_event, fn _event,
                                                                               _params,
                                                                               socket ->
            case Identity.scope_for_token(session["user_token"]) do
              nil -> {:halt, Phoenix.LiveView.redirect(socket, to: "/entrar")}
              current -> {:cont, Phoenix.Component.assign(socket, :current_scope, current)}
            end
          end)

        {:cont, socket}
    end
  end
end
