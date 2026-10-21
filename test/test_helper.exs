# Shared sandbox fixtures insert the same fictional organization; bound fixture contention.
# Independent runtime-role race tests still use separate concurrent database connections.
ExUnit.start(max_cases: 4)
Ecto.Adapters.SQL.Sandbox.mode(Instantflow.Repo, :manual)
