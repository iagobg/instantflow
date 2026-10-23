defmodule Instantflow.Demo.SetupSafetyTest do
  use ExUnit.Case, async: true
  alias Mix.Tasks.Instantflow.Demo.Setup

  @config [database: "instantflow_demo", hostname: "localhost", port: 55432]

  test "requires an explicit dev-only target and matching local connections before any DB task" do
    assert :ok =
             Setup.validate_target!(
               :dev,
               "instantflow_demo",
               "instantflow_demo",
               @config,
               @config
             )

    for {environment, requested, selected, runtime, operator} <- [
          {:prod, "instantflow_demo", "instantflow_demo", @config, @config},
          {:test, "instantflow_demo", "instantflow_demo", @config, @config},
          {:dev, nil, "instantflow_demo", @config, @config},
          {:dev, "instantflow_dev", "instantflow_demo", @config, @config},
          {:dev, "instantflow_demo", nil, @config, @config},
          {:dev, "instantflow_demo", "instantflow_demo",
           Keyword.put(@config, :database, "instantflow_dev"), @config},
          {:dev, "instantflow_demo", "instantflow_demo", @config,
           Keyword.put(@config, :database, "instantflow_dev")},
          {:dev, "instantflow_demo", "instantflow_demo", @config,
           Keyword.put(@config, :hostname, "remote.example")},
          {:dev, "instantflow_demo", "instantflow_demo", @config,
           Keyword.put(@config, :port, 5432)},
          {:dev, "instantflow_demo", "instantflow_demo",
           Keyword.put(@config, :url, "ecto://localhost/instantflow_dev"), @config},
          {:dev, "instantflow_demo", "instantflow_demo", @config,
           Keyword.put(@config, :socket_dir, "/tmp")}
        ] do
      assert_raise Mix.Error, fn ->
        Setup.validate_target!(environment, requested, selected, runtime, operator)
      end
    end
  end
end
