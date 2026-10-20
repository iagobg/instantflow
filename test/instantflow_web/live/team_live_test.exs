defmodule InstantflowWeb.TeamLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures

  test "admin generates a working invitation through the form", %{conn: conn} do
    admin = staff_fixture()
    {:ok, view, _} = live(login(conn, admin), ~p"/equipe")
    assert has_element?(view, "#staff")

    view
    |> form("#invite-form",
      invitation: %{
        email: "invited@escola.example",
        role: "staff",
        department_id: admin.department_id
      }
    )
    |> render_submit()

    assert has_element?(view, "#invitation-result")

    code =
      view
      |> element("#invitation-code")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.text()
      |> String.trim()

    assert {:ok, _} =
             Instantflow.Identity.accept_invitation(code, %{
               "name" => "Pessoa Convidada",
               "password" => "fictional-password-123"
             })
  end

  test "staff cannot access team management", %{conn: conn} do
    staff = staff_fixture("staff")
    assert {:error, {:live_redirect, %{to: "/"}}} = live(login(conn, staff), ~p"/equipe")
  end

  test "revoked sessions cannot submit on an already mounted screen", %{conn: conn} do
    admin = staff_fixture()
    token = Instantflow.Identity.create_session(admin.user)
    conn = Plug.Test.init_test_session(conn, user_token: token)
    {:ok, view, _} = live(conn, ~p"/equipe")
    Instantflow.Identity.delete_session(token)

    view
    |> form("#invite-form",
      invitation: %{
        email: "denied@escola.example",
        role: "staff",
        department_id: admin.department_id
      }
    )
    |> render_submit()

    assert_redirect(view, "/entrar")
    assert Instantflow.Repo.aggregate(Instantflow.Identity.Invitation, :count) == 0
  end

  test "overview links to workflow requests", %{conn: conn} do
    {:ok, view, _} = live(login(conn, staff_fixture()), ~p"/")
    assert has_element?(view, "#main-content")
    assert has_element?(view, "a[href='/solicitacoes']", "Abrir solicitações")
  end
end
