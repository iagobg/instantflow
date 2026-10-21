defmodule Instantflow.Identity.Invitation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "invitations" do
    field :email, :string
    belongs_to :enrollment, Instantflow.Enrollment.Record
    field :role, :string, default: "staff"
    field :token_hash, :binary, redact: true
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime
    belongs_to :organization, Instantflow.Identity.Organization
    belongs_to :department, Instantflow.Identity.Department
    belongs_to :invited_by, Instantflow.Identity.User
    timestamps(type: :utc_datetime)
  end

  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:email, :role])
    |> update_change(:email, &Instantflow.Identity.normalize_email/1)
    |> validate_required([:email, :role], message: "é obrigatório")
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/,
      message: "informe um e-mail válido"
    )
    |> validate_length(:email, max: 160, message: "deve ter no máximo 160 caracteres")
    |> validate_inclusion(:role, ["admin", "staff", "parent"],
      message: "selecione um perfil válido"
    )
  end
end
