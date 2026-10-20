defmodule Instantflow.IdentityTest do
  use Instantflow.DataCase, async: true
  import Instantflow.IdentityFixtures
  alias Instantflow.Identity
  alias Instantflow.Identity.{Invitation, Membership, Session, User}

  test "an invitation binds email, department and role and can only be accepted once" do
    admin = staff_fixture()

    {:ok, result} =
      Identity.invite(admin, %{
        "email" => " NEW@escola.example ",
        "role" => "staff",
        "department_id" => admin.department_id
      })

    attrs = %{
      "name" => "Nova Pessoa",
      "password" => "fictional-password-123",
      "email" => "forged@example.com",
      "role" => "admin"
    }

    assert {:ok, user} = Identity.accept_invitation(result.token, attrs)
    assert user.email == "new@escola.example"
    assert Identity.scope(user.id).role == "staff"
    assert {:error, :invalid_invitation} = Identity.accept_invitation(result.token, attrs)
    assert {:ok, _} = Identity.authenticate("NEW@escola.example", attrs["password"])
    assert Repo.get!(Invitation, result.invitation.id).token_hash != result.token
  end

  test "invalid account details roll back acceptance and permit a corrected retry" do
    admin = staff_fixture()

    {:ok, result} =
      Identity.invite(admin, %{
        "email" => "retry@escola.example",
        "role" => "staff",
        "department_id" => admin.department_id
      })

    assert {:error, %Ecto.Changeset{}} =
             Identity.accept_invitation(result.token, %{"name" => "A", "password" => "short"})

    assert Repo.get!(Invitation, result.invitation.id).accepted_at == nil
    assert Repo.get_by(User, email: "retry@escola.example") == nil

    assert {:ok, _} =
             Identity.accept_invitation(result.token, %{
               "name" => "Pessoa",
               "password" => "fictional-password-123"
             })
  end

  test "expired and invalid invitations are denied" do
    admin = staff_fixture()

    {:ok, result} =
      Identity.invite(admin, %{
        "email" => "expired@escola.example",
        "role" => "staff",
        "department_id" => admin.department_id
      })

    Repo.update!(
      Ecto.Changeset.change(result.invitation,
        expires_at: DateTime.add(DateTime.utc_now(:second), -1)
      )
    )

    assert {:error, :invalid_invitation} = Identity.accept_invitation(result.token, %{})
    assert {:error, :invalid_invitation} = Identity.accept_invitation("wrong", %{})
  end

  test "staff and stale administrator scopes cannot invite" do
    staff = staff_fixture("staff")
    assert {:error, :forbidden} = Identity.invite(staff, %{})
    admin = staff_fixture()
    Repo.update!(Ecto.Changeset.change(Repo.get!(Membership, admin.id), role: "staff"))
    assert {:error, :forbidden} = Identity.invite(admin, %{})
    assert Identity.list_staff(admin) == []
  end

  test "logout, expiration, and membership revocation invalidate sessions" do
    admin = staff_fixture()
    token = Identity.create_session(admin.user)
    assert Identity.scope_for_token(token).user_id == admin.user_id
    Identity.delete_session(token)
    assert Identity.scope_for_token(token) == nil
    token = Identity.create_session(admin.user)
    Repo.update_all(Session, set: [expires_at: DateTime.add(DateTime.utc_now(:second), -1)])
    assert Identity.scope_for_token(token) == nil
    token = Identity.create_session(admin.user)
    Repo.update!(Ecto.Changeset.change(Repo.get!(Membership, admin.id), active: false))
    assert Identity.scope_for_token(token) == nil

    assert {:error, :invalid_credentials} =
             Identity.authenticate(admin.user.email, "fictional-password-123")
  end

  test "password mismatch and invalid departments do not grant access" do
    admin = staff_fixture()
    assert {:error, :invalid_credentials} = Identity.authenticate(admin.user.email, "wrong")

    assert {:error, :invalid_credentials} =
             Identity.authenticate("unknown@escola.example", "wrong")

    assert {:error, :invalid_department} = Identity.invite(admin, %{"department_id" => -1})
  end
end
