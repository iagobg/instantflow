defmodule Instantflow.Organizations do
  alias Instantflow.{Identity, Repo}
  alias Instantflow.Identity.Organization

  def choices(%{id: id}) do
    %{rows: rows} = Repo.query!("SELECT * FROM organization_choices($1)", [id])

    Enum.map(rows, fn [id, slug, name, timezone, status] ->
      %Organization{id: id, slug: slug, name: name, timezone: timezone, status: status}
    end)
  end

  def choices(_), do: []

  def scope(user, slug) when is_binary(slug) do
    case Enum.find(choices(user), &(&1.slug == slug)) do
      nil -> nil
      organization -> Identity.scope(user.id, organization.id)
    end
  end

  def scope(_, _), do: nil

  def home(user) do
    case choices(user) do
      [organization] -> "/o/#{organization.slug}"
      _ -> "/organizacoes"
    end
  end
end
