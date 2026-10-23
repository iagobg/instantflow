defmodule InstantflowWeb.RetiredRoutesTest do
  use InstantflowWeb.ConnCase, async: true
  import Instantflow.IdentityFixtures

  test "retired domain URLs are unreachable even for authenticated administrators", %{conn: conn} do
    actor = staff_fixture()

    for route <- ~w(matriculas matriculas/1 ocorrencias orcamentos operacao operacao/1) do
      assert login(conn, actor) |> get("/o/horizonte/" <> route) |> response(404)
    end
  end
end
