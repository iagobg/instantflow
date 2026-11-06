defmodule InstantflowWeb.NavigationReuseLiveTest do
  use InstantflowWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  import Instantflow.WorkflowFixtures
  alias Instantflow.{NavigationProbe, Repo, Tenant, WorkflowCatalog}
  alias Instantflow.Diagnostics.QueryProbe

  test "routine events reuse navigation while periodic reconciliation rebuilds it", %{conn: conn} do
    f = workflow_fixture()
    id = create_ticket(f)
    {:ok, view, _} = live(login(conn, f.requester), ~p"/o/horizonte/solicitacoes/#{id}")
    _ = :sys.get_state(view.pid)

    {_, 0} = NavigationProbe.capture(view.pid, fn -> reason(view, "Current reason") end)

    {_, report} = QueryProbe.capture(fn -> reason(view, "Another reason") end, scope: :all)
    assert report.errors == 0

    if path = System.get_env("DB_EFFICIENCY_REPORT"),
      do: File.write!(path, Jason.encode!(report))

    {_, 1} =
      NavigationProbe.capture(view.pid, fn ->
        send(view.pid, :revalidate_organization)
        render(view)
        _ = :sys.get_state(view.pid)
      end)

    {_, 0} = NavigationProbe.capture(view.pid, fn -> reason(view, "Still current") end)
  end

  test "missed grant and role invalidations change navigation on the next protected event", %{
    conn: conn
  } do
    f = workflow_fixture()
    id = create_ticket(f)
    gated = publish(f, "gated_navigation", "Only operations", ["operations"])
    {:ok, view, _} = live(login(conn, f.requester), ~p"/o/horizonte/solicitacoes/#{id}")
    selector = "#process-link-#{gated.workflow_id}"
    refute has_element?(view, selector)

    grant =
      Repo.insert!(%Instantflow.Access.Grant{
        organization_id: 1,
        membership_id: f.requester.id,
        department_id: f.requester.department_id,
        role: "operations"
      })

    {_, 1} = NavigationProbe.capture(view.pid, fn -> reason(view, "Grant added") end)
    assert has_element?(view, selector)
    Repo.delete!(grant)
    reason(view, "Grant removed")
    refute has_element?(view, selector)

    promoted = Repo.update!(Ecto.Changeset.change(f.requester, role: "admin"))
    reason(view, "Role changed")
    assert has_element?(view, selector)
    Repo.update!(Ecto.Changeset.change(promoted, role: "staff"))
    reason(view, "Role removed")
    refute has_element?(view, selector)
  end

  test "a missed publication changing a label or access is detected in both tabs", %{conn: conn} do
    f = workflow_fixture()
    id = create_ticket(f)
    version = publish(f, "changing_navigation", "Before", ["staff"])
    {:ok, first, _} = live(login(conn, f.requester), ~p"/o/horizonte/solicitacoes/#{id}")
    {:ok, second, _} = live(login(build_conn(), f.requester), ~p"/o/horizonte/solicitacoes/#{id}")
    selector = "#process-link-#{version.workflow_id}"
    assert has_element?(first, selector, "Before")

    # Scoped publication without notify_publication simulates a missed broadcast.
    {:ok, v2} =
      Tenant.transaction(f.admin, fn fresh ->
        WorkflowCatalog.publish_scoped!(
          fresh,
          Map.put(version.definition, "name", "After"),
          version.bindings,
          1
        )
      end)

    for view <- [first, second] do
      reason(view, "Missed publication")
      assert has_element?(view, selector, "After")
    end

    {:ok, _} =
      Tenant.transaction(f.admin, fn fresh ->
        WorkflowCatalog.publish_scoped!(
          fresh,
          v2.definition,
          put_in(v2.bindings, ["roles", "requester"], ["operations"]),
          2
        )
      end)

    for view <- [first, second] do
      reason(view, "Access changed")
      refute has_element?(view, selector)
    end
  end

  test "navigation reuse never skips session expiry or membership revocation", %{conn: conn} do
    f = workflow_fixture()
    id = create_ticket(f)
    logged_in = login(conn, f.requester)
    {:ok, view, _} = live(logged_in, ~p"/o/horizonte/solicitacoes/#{id}")
    token = get_session(logged_in, :user_token)
    hash = :crypto.hash(:sha256, token)
    session = Repo.get_by!(Instantflow.Identity.Session, token_hash: hash)
    Repo.update!(Ecto.Changeset.change(session, expires_at: ~U[2020-01-01 00:00:00Z]))
    reason(view, "Expired session")
    assert_redirect(view, "/organizacoes")

    {:ok, other, _} = live(login(build_conn(), f.requester), ~p"/o/horizonte/solicitacoes/#{id}")
    Repo.update!(Ecto.Changeset.change(f.requester, active: false))
    reason(other, "Revoked membership")
    assert_redirect(other, "/organizacoes")
  end

  defp reason(view, value),
    do: view |> form("#transition-form", action: %{reason: value}) |> render_change()

  defp publish(f, key, label, roles) do
    definition = Instantflow.WorkflowCatalog.Templates.starter(key, label)

    {:ok, version} =
      WorkflowCatalog.publish(f.admin, definition, %{
        "roles" => %{"requester" => roles, "reviewer" => ["admin"]},
        "departments" => %{"responsible" => f.admin.department_id}
      })

    version
  end
end
