defmodule Instantflow.RuntimeDatabase do
  @moduledoc "Fail startup if ordinary application traffic is configured with privileged database credentials."
  def child_spec(_), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [[]]}}

  def start_link(_) do
    unless Application.get_env(:instantflow, :environment) == :test do
      %{rows: [[name, privileged, owns_tables]]} =
        Instantflow.Repo.query!(
          "SELECT current_user, r.rolsuper OR r.rolbypassrls OR r.rolcreaterole, EXISTS(SELECT FROM pg_tables WHERE schemaname='public' AND tableowner=current_user) FROM pg_roles r WHERE rolname=current_user"
        )

      if name != "instantflow_runtime" or privileged or owns_tables,
        do: raise("Runtime database credentials must be the non-owner instantflow_runtime role")
    end

    :ignore
  end
end
