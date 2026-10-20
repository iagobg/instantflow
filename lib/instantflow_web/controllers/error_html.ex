defmodule InstantflowWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use InstantflowWeb, :html

  # If you want to customize your error pages,
  # uncomment the embed_templates/1 call below
  # and add pages to the error directory:
  #
  #   * lib/instantflow_web/controllers/error_html/404.html.heex
  #   * lib/instantflow_web/controllers/error_html/500.html.heex
  #
  # embed_templates "error_html/*"

  # The default is to render a plain text page based on
  # the template name. For example, "404.html" becomes
  # "Página não encontrada".
  def render(template, _assigns) do
    message(template)
  end

  defp message("404.html"), do: "Página não encontrada"
  defp message("403.html"), do: "Acesso não permitido"
  defp message(_), do: "Não foi possível concluir a solicitação"
end
