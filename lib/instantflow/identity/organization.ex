defmodule Instantflow.Identity.Organization do
  use Ecto.Schema

  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :status, :string, default: "active"
    field :timezone, :string, default: "America/Sao_Paulo"
    field :catalog_generation, :integer, virtual: true, default: 0
    timestamps(type: :utc_datetime)
  end
end
