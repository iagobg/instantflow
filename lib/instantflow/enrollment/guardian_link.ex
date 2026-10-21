defmodule Instantflow.Enrollment.GuardianLink do
  use Ecto.Schema

  schema "guardian_links" do
    field :active, :boolean, default: true
    field :verified_at, :utc_datetime
    belongs_to :organization, Instantflow.Identity.Organization
    belongs_to :enrollment, Instantflow.Enrollment.Record
    belongs_to :membership, Instantflow.Identity.Membership
    belongs_to :verified_by, Instantflow.Identity.User
    timestamps(type: :utc_datetime)
  end
end
