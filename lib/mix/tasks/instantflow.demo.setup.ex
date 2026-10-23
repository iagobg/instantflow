defmodule Mix.Tasks.Instantflow.Demo.Setup do
  use Mix.Task

  @shortdoc "Prepare the explicitly selected disposable local school demo"
  @moduledoc """
  Prepares the first D01 purchasing scenario. Requires MIX_ENV=dev,
  INSTANTFLOW_DEMO_DATABASE=instantflow_demo and DEMO_PASSWORD (12–128 characters).

      mix instantflow.demo.setup --database instantflow_demo

  Repeat setup preserves passwords, published pins and presenter changes. Only
  --reset --database instantflow_demo drops data. Both repository connections
  must target the same loopback database. See docs/school-demo.md.
  """

  @impl true
  def run(args) do
    {options, rest} = OptionParser.parse!(args, strict: [database: :string, reset: :boolean])
    if rest != [], do: Mix.raise("Unexpected demo setup arguments")
    Mix.Task.run("app.config")

    validate_target!(
      Mix.env(),
      options[:database],
      System.get_env("INSTANTFLOW_DEMO_DATABASE"),
      Application.fetch_env!(:instantflow, Instantflow.Repo),
      Application.fetch_env!(:instantflow, Instantflow.OperatorRepo)
    )

    password = System.get_env("DEMO_PASSWORD")
    Instantflow.Demo.School.validate_password!(password)

    if options[:reset] do
      Mix.Task.run("ecto.drop", ["-r", "Instantflow.OperatorRepo"])
    end

    Mix.Task.run("ecto.create", ["-r", "Instantflow.OperatorRepo"])
    Mix.Task.run("ecto.migrate", ["-r", "Instantflow.OperatorRepo"])
    Mix.Task.run("app.start")
    {:ok, pid} = Instantflow.OperatorRepo.start_link()

    try do
      inventory = Instantflow.Demo.School.install!(password)
      Mix.shell().info(Jason.encode!(inventory, pretty: true))
    after
      GenServer.stop(pid)
    end
  end

  @doc false
  def validate_target!(environment, requested, selected, runtime, operator) do
    local? = fn config ->
      config[:database] == "instantflow_demo" and
        config[:hostname] in ["localhost", "127.0.0.1", "::1"] and
        is_nil(config[:url]) and is_nil(config[:socket_dir])
    end

    unless environment == :dev and requested == "instantflow_demo" and
             selected == "instantflow_demo" and local?.(runtime) and local?.(operator) and
             runtime[:hostname] == operator[:hostname] and runtime[:port] == operator[:port] do
      Mix.raise("Demo setup requires dev and explicit, matching local instantflow_demo targets")
    end

    :ok
  end
end
