defmodule Instantflow.Repo do
  use Ecto.Repo,
    otp_app: :instantflow,
    adapter: Ecto.Adapters.Postgres
end
