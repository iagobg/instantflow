defmodule Instantflow.OperatorRepo do
  @moduledoc "Migration/operator credentials. Never started by the web application."
  use Ecto.Repo, otp_app: :instantflow, adapter: Ecto.Adapters.Postgres
end
