defmodule Instantflow.Examples do
  @moduledoc "Optional example data installation through the supported catalog; never selected by the runtime."
  @examples ~w(enrollment incident requisition field_trip simple_approval resource_service)

  def definition(key) when key in @examples do
    Application.app_dir(:instantflow, "priv/workflows/#{key}.json")
    |> File.read!()
    |> Jason.decode!()
  end

  def install(actor, key, bindings),
    do: Instantflow.WorkflowCatalog.publish(actor, definition(key), bindings)
end
