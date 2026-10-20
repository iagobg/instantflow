defmodule Instantflow.Identity.Session do
  use Ecto.Schema

  schema "sessions" do
    field :token_hash, :binary, redact: true
    field :expires_at, :utc_datetime
    belongs_to :user, Instantflow.Identity.User
    timestamps(type: :utc_datetime)
  end
end
