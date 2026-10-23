defmodule InstantflowWeb.PaginationControls do
  @moduledoc "Accessible deterministic page controls for authorized result collections."
  use InstantflowWeb, :html

  attr :id, :string, required: true
  attr :info, :map, required: true
  attr :event, :string, required: true
  attr :kind, :string, default: nil
  attr :label, :string, default: "resultado(s)"

  def pagination(assigns) do
    ~H"""
    <p id={@id <> "-count"}>{@info.total} {@label} · Página {@info.page} de {@info.pages}</p>
    <nav :if={@info.pages > 1} id={@id <> "-pagination"} aria-label="Páginas de resultados">
      <button
        type="button"
        class="btn"
        id={@id <> "-previous"}
        phx-click={@event}
        phx-value-kind={@kind}
        phx-value-page={@info.page - 1}
        disabled={@info.page <= 1}
      >Anterior</button>
      <button
        type="button"
        class="btn"
        id={@id <> "-next"}
        phx-click={@event}
        phx-value-kind={@kind}
        phx-value-page={@info.page + 1}
        disabled={@info.page >= @info.pages}
      >Próxima</button>
    </nav>
    """
  end
end
