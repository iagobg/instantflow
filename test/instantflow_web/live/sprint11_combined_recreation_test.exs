defmodule InstantflowWeb.Sprint11CombinedRecreationTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  alias Instantflow.{Access, Finance, Identity, Repo, Sprint11AcceptanceFixtures, WorkflowRuntime}
  alias Instantflow.Identity.{Organization, Department, Membership, User}
  alias Instantflow.WorkflowCatalog.{Interchange, Templates, Version, Workspaces}

  test "six independent processes coexist from empty organizations with UI mappings and shared identity local grants" do
    admin = staff_fixture()
    assert Repo.aggregate(Version, :count) == 0

    org =
      Repo.insert!(%Organization{id: 2, slug: "second-builder", name: "Second synthetic builder"})

    dep = Repo.insert!(%Department{organization_id: org.id, name: "Local team"})

    user =
      Repo.insert!(
        User.changeset(%User{email: "second-admin@example.test"}, %{
          name: "Local admin",
          password: "fictional-password-123"
        })
      )

    Repo.insert!(%Membership{
      organization_id: org.id,
      department_id: dep.id,
      user_id: user.id,
      role: "admin"
    })

    member =
      Repo.insert!(%Membership{
        organization_id: org.id,
        department_id: dep.id,
        user_id: admin.user_id,
        role: "staff"
      })

    local_admin = Identity.scope(user.id, org.id)
    shared = Identity.scope(admin.user_id, org.id)

    for {owner, role} <- [{admin, "admin"}, {local_admin, "operations"}] do
      {:ok, account} =
        Finance.create_account(owner, owner.department_id, "Local synthetic budget")

      for definition <- Sprint11AcceptanceFixtures.definitions() do
        {:ok, draft} = Templates.import(owner, Interchange.encode(definition))

        {:ok, editor, _} =
          live(login(build_conn(), owner), "/o/#{owner.organization.slug}/modelos/#{draft.id}")

        bindings = Sprint11AcceptanceFixtures.bindings(owner, definition, account.id, role)
        mapping = Map.put(bindings, "assignment", definition["assignment"]["department_binding"])
        editor |> form("#template-mappings", mapping: mapping) |> render_submit()
        refute has_element?(editor, "#publish-template[disabled]")
        editor |> element("#publish-template") |> render_click()
        editor |> element("#confirm-publish-template") |> render_click()
        {:ok, published} = Templates.get(owner, draft.id)
        assert published.published_version_id
      end
    end

    assert Workspaces.search(admin).total == 6
    assert Workspaces.search(shared).total == 0
    {:ok, {_, grant}} = Access.grant(local_admin, member.id, dep.id, "operations")
    assert Workspaces.search(shared).total == 6
    [first | _] = Workspaces.search(shared).rows

    assert {:ok, _} =
             WorkflowRuntime.command(shared, %{
               "operation" => "create",
               "workflow_id" => first.workflow_id,
               "key" => Ecto.UUID.generate()
             })

    own = hd(Workspaces.search(admin).rows)

    assert {:error, _} =
             WorkflowRuntime.command(shared, %{
               "operation" => "create",
               "workflow_id" => own.workflow_id,
               "key" => Ecto.UUID.generate()
             })

    {:ok, _} = Access.revoke(local_admin, grant.id)
    assert Workspaces.search(shared).total == 0
    assert Workspaces.search(admin).total == 6
  end
end
