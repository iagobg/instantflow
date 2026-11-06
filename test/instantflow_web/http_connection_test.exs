defmodule InstantflowWeb.HttpConnectionTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  alias Instantflow.Repo
  @endpoint InstantflowWeb.Endpoint

  test "pages without database reads remain available while the pool is occupied" do
    runtime =
      start_supervised!(
        {Repo,
         name: :http_connection_test,
         pool: DBConnection.ConnectionPool,
         pool_size: 1,
         timeout: 250}
      )

    Repo.put_dynamic_repo(runtime)
    Repo.query!("SELECT 1")
    tasks = start_supervised!(Task.Supervisor)
    parent = self()

    holder =
      Task.Supervisor.async_nolink(tasks, fn ->
        Repo.put_dynamic_repo(runtime)

        Repo.checkout(
          fn ->
            send(parent, :holding)
            receive do: (:release -> :ok)
          end,
          timeout: :infinity
        )
      end)

    assert_receive :holding

    try do
      assert get(build_conn(), "/entrar").status == 200
      assert get(build_conn(), "/convite").status == 200
      assert redirected_to(get(build_conn(), "/")) == "/entrar"
    after
      send(holder.pid, :release)
      Task.await(holder)
    end
  end
end
