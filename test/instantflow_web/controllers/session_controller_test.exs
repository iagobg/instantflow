defmodule InstantflowWeb.SessionControllerTest do
  use InstantflowWeb.ConnCase, async: true
  import Instantflow.IdentityFixtures

  test "internal routes require authentication", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/")) == "/entrar"
    assert redirected_to(get(conn, ~p"/o/horizonte/equipe")) == "/entrar"
  end

  test "login and logout use a revocable server-side session", %{conn: conn} do
    staff = staff_fixture()

    conn =
      post(conn, ~p"/entrar",
        login: %{email: staff.user.email, password: "fictional-password-123"}
      )

    token = get_session(conn, :user_token)
    assert redirected_to(conn) == "/o/horizonte"
    assert Instantflow.Identity.scope_for_token(token, 1)
    conn = conn |> recycle() |> delete(~p"/sair")
    assert redirected_to(conn) == "/entrar"
    assert Instantflow.Identity.scope_for_token(token, 1) == nil
  end

  test "bad credentials display a PT-BR error without reflecting the password", %{conn: conn} do
    conn =
      post(conn, ~p"/entrar",
        login: %{email: "missing@example.com", password: "never-reflect-this"}
      )

    assert html_response(conn, 422) =~ "E-mail ou senha inválidos"
    refute conn.resp_body =~ "never-reflect-this"
  end
end
