defmodule InstantflowWeb.OrganizationController do
  use InstantflowWeb, :controller

  def home(conn, _),
    do: redirect(conn, to: Instantflow.Organizations.home(conn.assigns.current_user))

  def index(conn, _),
    do:
      render(conn, :index,
        organizations: Instantflow.Organizations.choices(conn.assigns.current_user)
      )
end
