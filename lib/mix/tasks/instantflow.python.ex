defmodule Mix.Tasks.Instantflow.Python do
  use Mix.Task
  @shortdoc "Operator-only durable calculation enable/disable switch"
  @moduledoc """
  mix instantflow.python enable|disable
  Uses OperatorRepo, increments the fencing generation and records a data-free switch audit.
  Disable first, then remove the broker's ENABLED file to kill active containers.
  Enabling does not certify the runtime or enable the serving node's PYTHON_EXECUTION setting.
  """
  def run([operation]) when operation in ~w(enable disable) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, pid} = Instantflow.OperatorRepo.start_link()

    Instantflow.OperatorRepo.transaction(fn ->
      Instantflow.OperatorRepo.query!(
        "WITH changed AS (UPDATE calculation_switch SET enabled = $1, generation = generation + 1 WHERE id = 1 RETURNING enabled, generation) INSERT INTO calculation_switch_events (enabled, generation, operator, inserted_at) SELECT enabled, generation, current_user, now() FROM changed",
        [operation == "enable"]
      )
    end)

    Mix.shell().info("Python switch: #{operation}; previous generations cannot apply results.")
    GenServer.stop(pid)
  end

  def run(_), do: Mix.raise("Usage: mix instantflow.python enable|disable")
end
