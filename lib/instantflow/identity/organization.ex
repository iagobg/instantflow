defmodule Instantflow.Identity.Organization do
  use Ecto.Schema

  schema "organizations" do
    field :name, :string
    field :timezone, :string, default: "America/Sao_Paulo"
    timestamps(type: :utc_datetime)
  end
end
