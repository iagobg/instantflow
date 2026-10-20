defmodule InstantflowWeb.SessionController do
  use InstantflowWeb, :controller
  alias Instantflow.Identity

  def new(conn, _params) do
    if conn.assigns.current_scope,
      do: redirect(conn, to: ~p"/"),
      else: render(conn, :new, form: Phoenix.Component.to_form(%{}, as: :login))
  end

  def create(conn, %{"login" => params}) do
    case Identity.authenticate(params["email"], params["password"]) do
      {:ok, user} ->
        Identity.delete_session(get_session(conn, :user_token))
        token = Identity.create_session(user)

        conn
        |> configure_session(renew: true)
        |> clear_session()
        |> put_session(:user_token, token)
        |> put_session(:live_socket_id, Identity.socket_id(token))
        |> redirect(to: ~p"/")

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_flash(
          :error,
          "E-mail ou senha inválidos. Verifique também se seu acesso está ativo."
        )
        |> render(:new,
          form: Phoenix.Component.to_form(%{"email" => params["email"]}, as: :login)
        )
    end
  end

  def delete(conn, _params) do
    Identity.delete_session(get_session(conn, :user_token))
    conn |> configure_session(drop: true) |> redirect(to: ~p"/entrar")
  end

  def invitation(conn, _params),
    do: render(conn, :invitation, form: Phoenix.Component.to_form(%{}, as: :account))

  def accept(conn, %{"account" => params}) do
    case Identity.accept_invitation(params["code"], params) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Conta criada. Entre com seu e-mail e senha.")
        |> redirect(to: ~p"/entrar")

      {:error, error} ->
        message =
          if is_struct(error, Ecto.Changeset),
            do:
              "Revise seu nome e senha (12 a 128 caracteres). O e-mail pode já possuir uma conta.",
            else: "Convite inválido, expirado ou já utilizado. Solicite um novo código."

        conn
        |> put_status(:unprocessable_entity)
        |> put_flash(:error, message)
        |> render(:invitation,
          form: Phoenix.Component.to_form(Map.take(params, ["name"]), as: :account)
        )
    end
  end
end
