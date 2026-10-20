import Config
config :instantflow, :delivery_worker, false

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :instantflow, Instantflow.Repo,
  # Privileged fixture setup only; scoped calls SET LOCAL ROLE and dedicated tests use a real runtime login.
  username: System.get_env("MIGRATION_PGUSER", "postgres"),
  password: System.get_env("MIGRATION_PGPASSWORD", "instantflow-local-only"),
  hostname: System.get_env("PGHOST", "localhost"),
  port: String.to_integer(System.get_env("PGPORT", "55432")),
  database: "instantflow_test#{System.get_env("MIX_TEST_PARTITION")}",
  template: "template0",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 12

config :instantflow, Instantflow.OperatorRepo,
  priv: "priv/repo",
  log: false,
  username: System.get_env("MIGRATION_PGUSER", "postgres"),
  password: System.get_env("MIGRATION_PGPASSWORD", "instantflow-local-only"),
  hostname: System.get_env("PGHOST", "localhost"),
  port: String.to_integer(System.get_env("PGPORT", "55432")),
  database:
    System.get_env("MIGRATION_DATABASE") ||
      "instantflow_test#{System.get_env("MIX_TEST_PARTITION")}",
  template: "template0",
  pool_size: 12

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :instantflow, InstantflowWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "SQbzDUEmAnX1JvgsfDrXAMP0rwMeQDjI2tVUtpRaTAIOE/GPQxWidMmt6PILew3O",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
