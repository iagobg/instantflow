defmodule InstantflowWeb.RouterConnection do
  @moduledoc "Keep one connection lease through router authentication and rendering, with normal context-owned transactions."
  def init(options), do: InstantflowWeb.Router.init(options)

  def call(conn, options) do
    Instantflow.Tenant.with_connection(fn -> InstantflowWeb.Router.call(conn, options) end)
  end
end
