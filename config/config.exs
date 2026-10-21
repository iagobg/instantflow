# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :mime, :types, %{"text/x-python" => ["py"]}

config :instantflow,
  environment: config_env(),
  delivery_poll_interval_ms: 250,
  ecto_repos: [Instantflow.Repo],
  generators: [timestamp_type: :utc_datetime]

config :phoenix, :filter_parameters, [
  "password",
  "token",
  "code",
  "password_hash",
  "application",
  "section",
  "values",
  "message",
  "content",
  "filename"
]

config :instantflow, Instantflow.Repo, log: false

# Configure the endpoint
config :instantflow, InstantflowWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: InstantflowWeb.ErrorHTML, json: InstantflowWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Instantflow.PubSub,
  live_view: [signing_salt: "rVdUn34K"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  instantflow: [
    args:
      ~w(js/app.js css/app.css --bundle --target=es2022 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
