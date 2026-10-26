defmodule Instantflow.IdentityFixtures do
  alias Instantflow.Repo
  alias Instantflow.Identity.{Department, Membership, Organization, User}

  def staff_fixture(role \\ "admin") do
    # Explicit fixture ID 1 does not advance PostgreSQL's sequence. Consume a value
    # so subsequent generated IDs cannot collide on a freshly migrated database.
    Repo.query!("SELECT nextval(pg_get_serial_sequence('organizations', 'id'))")

    Repo.insert!(%Organization{id: 1, slug: "horizonte", name: "Escola de Teste"},
      on_conflict: :nothing
    )

    Repo.insert!(%Department{organization_id: 1, name: "Secretaria"}, on_conflict: :nothing)
    department = Repo.get_by!(Department, organization_id: 1, name: "Secretaria")
    email = "person#{System.unique_integer([:positive])}@escola.example"

    user =
      Repo.insert!(
        User.changeset(%User{email: email}, %{
          name: "Pessoa Fictícia",
          password: "fictional-password-123"
        })
      )

    Repo.insert!(%Membership{
      organization_id: 1,
      department_id: department.id,
      user_id: user.id,
      role: role
    })

    Instantflow.Identity.scope(user.id, 1)
  end

  def login(conn, scope) do
    Plug.Test.init_test_session(conn, user_token: Instantflow.Identity.create_session(scope.user))
  end
end
