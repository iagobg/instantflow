defmodule Instantflow.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    delivery =
      if Application.get_env(:instantflow, :delivery_worker, true),
        do: [Instantflow.Delivery.Worker],
        else: []

    children =
      [
        InstantflowWeb.Telemetry,
        Instantflow.Repo,
        {DNSCluster, query: Application.get_env(:instantflow, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Instantflow.PubSub},
        # Start to serve requests, typically the last entry
        InstantflowWeb.Endpoint
      ] ++ delivery

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Instantflow.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    InstantflowWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
