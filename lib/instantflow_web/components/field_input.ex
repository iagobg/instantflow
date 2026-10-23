defmodule InstantflowWeb.FieldInput do
  @moduledoc "Generated field controls shared by staff and participant forms."
  use Phoenix.Component
  import InstantflowWeb.CoreComponents, only: [input: 1]

  attr :field, Phoenix.HTML.FormField, required: true
  attr :id, :string, required: true
  attr :type, :string, required: true
  attr :label, :string, required: true
  attr :options, :list, default: []
  attr :disabled, :boolean, default: false

  def field_input(assigns) do
    assigns =
      assigns
      |> assign(:input_type, input_type(assigns.type))
      |> assign(:input_options, input_options(assigns.type, assigns.options))

    ~H"""
    <.input
      field={@field}
      id={@id}
      label={@label}
      type={@input_type}
      options={@input_options}
      multiple={@type == "multiple_choice"}
      disabled={@disabled}
      min={if @type == "money", do: 0}
      step={if @type in ~w(integer money), do: 1}
      placeholder={if @type == "datetime", do: "2026-10-23T14:00:00-03:00"}
    />
    """
  end

  defp input_type("long_text"), do: "textarea"
  defp input_type(type) when type in ~w(integer money), do: "number"

  defp input_type(type)
       when type in ~w(boolean single_choice multiple_choice directory_reference),
       do: "select"

  defp input_type("date"), do: "date"
  # An instant requires its explicit offset; datetime-local would discard it.
  defp input_type(_), do: "text"

  defp input_options("boolean", _),
    do: [{"Não informado", ""}, {"Sim", "true"}, {"Não", "false"}]

  defp input_options("single_choice", options), do: [{"Não informado", ""} | options]
  defp input_options(_, options), do: options
end
