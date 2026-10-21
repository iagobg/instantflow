defmodule Instantflow.Calculations.Run do
  use Ecto.Schema

  schema "calculation_runs" do
    field :organization_id, :integer
    field :ticket_id, :integer
    field :script_id, :integer
    field :membership_id, :integer
    field :action_key, :string
    field :spec, :map
    field :snapshot, :map
    field :revisions, :map
    field :stage, :string
    field :stage_revision, :integer
    field :generation, :integer
    field :review_generation, :integer
    field :status, :string, default: "queued"
    field :attempts, :integer, default: 0
    field :fence, Ecto.UUID
    field :lease_until, :utc_datetime_usec
    field :output, :map
    field :diagnostic, :string
    timestamps(type: :utc_datetime_usec)
  end
end
