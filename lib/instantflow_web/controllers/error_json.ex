defmodule InstantflowWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  # If you want to customize a particular status code,
  # you may add your own clauses, such as:
  #
  # def render("500.json", _assigns) do
  #   %{errors: %{detail: "Não foi possível concluir a solicitação"}}
  # end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Página não encontrada".
  def render(template, _assigns) do
    %{
      errors: %{
        detail:
          if(template == "404.json",
            do: "Página não encontrada",
            else: "Não foi possível concluir a solicitação"
          )
      }
    }
  end
end
