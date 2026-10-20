defmodule Instantflow.Identity do
  @moduledoc "Invitation-only identity for the single demo organization."
  import Ecto.Query
  alias Instantflow.Repo

  alias Instantflow.Identity.{
    Department,
    Invitation,
    Membership,
    Organization,
    Password,
    Session,
    User
  }

  def normalize_email(email), do: email |> String.trim() |> String.downcase()
  def organization, do: Repo.get!(Organization, 1)

  def departments,
    do: Repo.all(from d in Department, where: d.organization_id == 1, order_by: d.name)

  def scope(user_id) do
    Repo.one(
      from m in Membership,
        join: u in assoc(m, :user),
        where: u.id == ^user_id and u.active and m.active and m.organization_id == 1,
        preload: [:user, :department, :organization]
    )
  end

  def admin?(%Membership{user_id: id}) do
    case scope(id) do
      %Membership{role: "admin"} -> true
      _ -> false
    end
  end

  def admin?(_), do: false

  def list_staff(actor) do
    if admin?(actor) do
      Repo.all(
        from m in Membership,
          where: m.organization_id == 1,
          preload: [:user, :department],
          order_by: m.id
      )
    else
      []
    end
  end

  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: normalize_email(email))

    valid? =
      if user, do: Password.valid?(password, user.password_hash), else: Password.dummy_verify()

    if valid? and user.active and scope(user.id),
      do: {:ok, user},
      else: {:error, :invalid_credentials}
  end

  def authenticate(_, _), do: {:error, :invalid_credentials}

  def create_session(user) do
    token = token()

    Repo.insert!(%Session{
      user_id: user.id,
      token_hash: digest(token),
      expires_at: DateTime.add(now(), 86400)
    })

    token
  end

  def scope_for_token(token) when is_binary(token) and byte_size(token) <= 128 do
    case Repo.one(
           from s in Session, where: s.token_hash == ^digest(token) and s.expires_at > ^now()
         ) do
      nil -> nil
      session -> scope(session.user_id)
    end
  end

  def scope_for_token(_), do: nil

  def delete_session(token) when is_binary(token) do
    Repo.delete_all(from s in Session, where: s.token_hash == ^digest(token))
    InstantflowWeb.Endpoint.broadcast(socket_id(token), "disconnect", %{})
    :ok
  end

  def delete_session(_), do: :ok
  def socket_id(token), do: "sessions:" <> Base.url_encode64(digest(token), padding: false)

  def invite(actor, attrs) do
    Repo.transaction(fn ->
      lock_admin!(actor)

      department =
        Repo.get_by(Department, id: department_id(attrs["department_id"]), organization_id: 1)

      if is_nil(department), do: Repo.rollback(:invalid_department)
      token = token()

      invitation = %Invitation{
        organization_id: 1,
        department_id: department.id,
        invited_by_id: actor.user_id,
        token_hash: digest(token),
        expires_at: DateTime.add(now(), 172_800)
      }

      case Repo.insert(Invitation.changeset(invitation, attrs)) do
        {:ok, invitation} -> %{invitation: invitation, token: token}
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def accept_invitation(token, attrs) when is_binary(token) and byte_size(token) <= 128 do
    Repo.transaction(fn ->
      invitation =
        Repo.one(from i in Invitation, where: i.token_hash == ^digest(token), lock: "FOR UPDATE")

      if is_nil(invitation) or not is_nil(invitation.accepted_at) or
           DateTime.compare(invitation.expires_at, now()) != :gt,
         do: Repo.rollback(:invalid_invitation)

      user =
        case Repo.insert(User.changeset(%User{email: invitation.email}, attrs)) do
          {:ok, user} -> user
          {:error, changeset} -> Repo.rollback(changeset)
        end

      Repo.insert!(%Membership{
        user_id: user.id,
        organization_id: invitation.organization_id,
        department_id: invitation.department_id,
        role: invitation.role
      })

      invitation |> Ecto.Changeset.change(accepted_at: now()) |> Repo.update!()
      user
    end)
  end

  def accept_invitation(_, _), do: {:error, :invalid_invitation}
  # Lock order: user, membership, business rows. Revocation must follow the same order.
  defp lock_admin!(%Membership{user_id: id}) do
    user = Repo.one(from u in User, where: u.id == ^id, lock: "FOR UPDATE")

    member =
      Repo.one(
        from m in Membership,
          where: m.user_id == ^id and m.organization_id == 1,
          lock: "FOR UPDATE"
      )

    unless user && user.active && member && member.active && member.role == "admin",
      do: Repo.rollback(:forbidden)
  end

  defp lock_admin!(_), do: Repo.rollback(:forbidden)
  defp token, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  defp department_id(value) when is_integer(value), do: value

  defp department_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 and id < 9_223_372_036_854_775_807 -> id
      _ -> -1
    end
  end

  defp department_id(_), do: -1
  defp digest(token), do: :crypto.hash(:sha256, token)
  defp now, do: DateTime.utc_now(:second)
end
