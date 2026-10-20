defmodule InstantflowWeb.ErrorHTMLTest do
  use InstantflowWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    assert render_to_string(InstantflowWeb.ErrorHTML, "404", "html", []) ==
             "Página não encontrada"
  end

  test "renders 500.html" do
    assert render_to_string(InstantflowWeb.ErrorHTML, "500", "html", []) ==
             "Não foi possível concluir a solicitação"
  end
end
