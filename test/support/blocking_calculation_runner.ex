defmodule Instantflow.BlockingCalculationRunner do
  @moduledoc false
  def execute(request) do
    send(
      Application.fetch_env!(:instantflow, :calculation_test_observer),
      {:runner_waiting, self(), Instantflow.Repo.in_transaction?()}
    )

    receive do
      :release -> Instantflow.CalculationFixtures.execute(request)
    after
      5000 -> {:error, :test_barrier_timeout}
    end
  end
end
