defmodule InstantflowWeb.CoreComponents do
  use Phoenix.Component

  attr :field, Phoenix.HTML.FormField, default: nil
  attr :id, :string, default: nil
  attr :name, :string, default: nil
  attr :value, :any, default: nil
  attr :type, :string, default: "text"
  attr :label, :string, required: true
  attr :options, :list, default: []
  attr :prompt, :string, default: nil
  attr :errors, :list, default: []
  attr :rest, :global, include: ~w(required autocomplete minlength maxlength placeholder)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors =
      if Phoenix.Component.used_input?(field),
        do: Enum.map(field.errors, &translate_error/1),
        else: []

    assigns
    |> assign(
      field: nil,
      id: assigns.id || field.id,
      name: field.name,
      value: field.value,
      errors: errors
    )
    |> input()
  end

  def input(assigns) do
    ~H"""
    <div class="form-field">
      <label for={@id}>{@label}</label>
      <select
        :if={@type == "select"}
        id={@id}
        name={@name}
        aria-invalid={@errors != []}
        aria-describedby={if @errors != [], do: "#{@id}-errors"}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <input
        :if={@type != "select"}
        type={@type}
        id={@id}
        name={@name}
        value={if @type == "password", do: nil, else: @value}
        aria-invalid={@errors != []}
        aria-describedby={if @errors != [], do: "#{@id}-errors"}
        {@rest}
      />
      <div :if={@errors != []} id={"#{@id}-errors"} class="field-error" role="alert">
        <p :for={error <- @errors}>{error}</p>
      </div>
    </div>
    """
  end

  defp translate_error({message, opts}),
    do:
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)

  attr :name, :string, required: true
  attr :class, :string, default: ""

  def icon(assigns) do
    paths = %{
      "hero-arrow-right" => "M4 12h16m-6-6 6 6-6 6",
      "hero-squares-2x2" => "M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z",
      "hero-users" =>
        "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M16 3a4 4 0 0 1 0 8M22 21v-2a4 4 0 0 0-3-3.87M13 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0",
      "hero-building-office" =>
        "M4 21V3h12v18M16 10h4v11M2 21h20M8 7h4M8 11h4M8 15h4M9 21v-3h2v3",
      "hero-information-circle" =>
        "M12 8h.01M11 12h1v5h1M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0",
      "hero-arrow-right-on-rectangle" => "M9 5H4v14h5M10 12h12m-5-5 5 5-5 5",
      "hero-moon" => "M21 13A9 9 0 0 1 11 3 9 9 0 1 0 21 13"
    }

    assigns = assign(assigns, :path, Map.fetch!(paths, assigns.name))

    ~H"""
    <svg
      class={["icon", @class]}
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.7"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    ><path d={@path} /></svg>
    """
  end
end
