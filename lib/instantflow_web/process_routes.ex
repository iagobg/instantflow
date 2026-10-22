defmodule InstantflowWeb.ProcessRoutes do
  @moduledoc "Generated process URLs, independent of domain names and template keys."
  use InstantflowWeb, :verified_routes

  def page_path(scope, workflow_id, page, nil),
    do: ~p"/o/#{scope.organization.slug}/processos/#{workflow_id}/p/#{page}"

  def page_path(scope, workflow_id, page, id),
    do: ~p"/o/#{scope.organization.slug}/processos/#{workflow_id}/p/#{page}/atendimentos/#{id}"

  def session_path(scope, workflow_id, pages, id) do
    page =
      Enum.find(pages, &("items" in &1["blocks"])) ||
        Enum.find(pages, &("resources" in &1["blocks"])) || hd(pages)

    page_path(scope, workflow_id, page["key"], id)
  end
end
