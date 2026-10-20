defmodule InstantflowWeb.OrganizationLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  import Instantflow.WorkflowFixtures
  alias Instantflow.{Identity, Repo}
  alias Instantflow.Identity.{Department, Membership, Organization}

  test "two tabs keep their own organization and forged event data cannot retarget a command", %{
    conn: conn
  } do
    f = workflow_fixture()

    organization =
      Repo.insert!(%Organization{
        id: System.unique_integer([:positive]) + 10000,
        slug: "other-#{System.unique_integer([:positive])}",
        name: "Outra Escola"
      })

    department = Repo.insert!(%Department{organization_id: organization.id, name: "Secretaria"})

    Repo.insert!(%Membership{
      organization_id: organization.id,
      user_id: f.admin.user_id,
      department_id: department.id,
      role: "staff"
    })

    conn = login(conn, f.admin)
    {:ok, tab_a, _} = live(conn, ~p"/o/horizonte/equipe")
    {:ok, tab_b, _} = live(conn, ~p"/o/#{organization.slug}")
    assert has_element?(tab_b, "h2", "Outra Escola")
    refute has_element?(tab_b, "a[href='/o/#{organization.slug}/equipe']")

    render_submit(tab_a, "invite", %{
      "invitation" => %{
        "email" => "tabtest@example.com",
        "role" => "staff",
        "department_id" => f.admin.department_id,
        "organization_id" => organization.id
      }
    })

    invitation = Repo.get_by!(Instantflow.Identity.Invitation, email: "tabtest@example.com")
    assert invitation.organization_id == f.admin.organization_id

    assert {:error, {:live_redirect, %{to: path}}} =
             live(conn, ~p"/o/#{organization.slug}/equipe")

    assert path == "/o/#{organization.slug}"
    assert has_element?(tab_a, "#invite-form")
  end

  test "revocation clears the affected live tab while another organization remains available", %{
    conn: conn
  } do
    f = workflow_fixture()

    organization =
      Repo.insert!(%Organization{
        id: System.unique_integer([:positive]) + 10000,
        slug: "revoked-#{System.unique_integer([:positive])}",
        name: "Outra Escola"
      })

    department = Repo.insert!(%Department{organization_id: organization.id, name: "Secretaria"})

    member =
      Repo.insert!(%Membership{
        organization_id: organization.id,
        user_id: f.admin.user_id,
        department_id: department.id,
        role: "staff"
      })

    conn = login(conn, f.admin)
    {:ok, tab_a, _} = live(conn, ~p"/o/horizonte/equipe")
    {:ok, tab_b, _} = live(conn, ~p"/o/#{organization.slug}")
    Repo.update!(Ecto.Changeset.change(member, active: false))

    Phoenix.PubSub.broadcast(
      Instantflow.PubSub,
      "organization:#{organization.id}:user:#{f.admin.user_id}",
      :access_revoked
    )

    assert_redirect(tab_b, "/organizacoes")
    assert has_element?(tab_a, "#invite-form")
    assert Identity.scope(f.admin.user_id, organization.id) == nil
    assert Identity.scope(f.admin.user_id, f.admin.organization_id)
  end

  test "global sign-in with no available memberships reaches the access-unavailable picker", %{
    conn: conn
  } do
    f = workflow_fixture()
    Repo.update!(Ecto.Changeset.change(Repo.get!(Membership, f.admin.id), active: false))
    conn = login(conn, f.admin) |> get(~p"/organizacoes")
    assert html_response(conn, 200) =~ "Nenhuma organização disponível"
  end
end
