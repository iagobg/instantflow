defmodule InstantflowWeb.ErrorJSONTest do
  use InstantflowWeb.ConnCase, async: true

  test "renders 404" do
    assert InstantflowWeb.ErrorJSON.render("404.json", %{}) == %{
             errors: %{detail: "Página não encontrada"}
           }
  end

  test "renders 500" do
    assert InstantflowWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Não foi possível concluir a solicitação"}}
  end
end
