defmodule Instantflow.Collaboration.Assignment do
  use Ecto.Schema

  schema "section_assignments" do
    field :organization_id, :integer
    field :ticket_id, :integer
    field :section_key, :string
    field :membership_id, :integer
  end
end
