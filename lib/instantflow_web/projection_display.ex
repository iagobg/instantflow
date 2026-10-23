defmodule InstantflowWeb.ProjectionDisplay do
  @moduledoc "Bounded list previews; full typed values remain in record detail and immutable messages."
  @limit 80
  def preview(value) do
    text = display(value)
    if String.length(text) > @limit, do: String.slice(text, 0, @limit) <> "…", else: text
  end

  defp display(nil), do: "—"
  defp display(true), do: "Sim"
  defp display(false), do: "Não"
  defp display(list) when is_list(list), do: Enum.join(list, ", ")
  defp display(value), do: to_string(value)
end
