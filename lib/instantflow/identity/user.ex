defmodule Instantflow.Identity.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string
    field :password_hash, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :active, :boolean, default: true
    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :password])
    |> validate_required([:name, :password], message: "é obrigatório")
    |> validate_length(:name, min: 2, max: 100, message: "deve ter entre 2 e 100 caracteres")
    |> validate_length(:password,
      min: 12,
      max: 128,
      message: "deve ter entre 12 e 128 caracteres"
    )
    |> unique_constraint(:email, message: "já possui uma conta")
    |> hash_password()
  end

  defp hash_password(%{valid?: true} = changeset) do
    case get_change(changeset, :password) do
      nil ->
        changeset

      password ->
        put_change(changeset, :password_hash, Instantflow.Identity.Password.hash(password))
    end
  end

  defp hash_password(changeset), do: changeset
end
