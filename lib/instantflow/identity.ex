defmodule Instantflow.Identity do
  @moduledoc "Global authentication with explicit, independent organization memberships."
  import Ecto.Query
  alias Instantflow.{Repo, Tenant}
  alias Instantflow.Identity.{Department, Invitation, Membership, Password, Session, User}

  def normalize_email(email), do: email |> String.trim() |> String.downcase()
  def scope(user_id, organization_id), do: Tenant.scope(user_id, organization_id)

  def scope_for_token(token, organization_id) do
    case user_for_token(token) do
      nil -> nil
      user -> scope(user.id, organization_id)
    end
  end

  def departments(actor),
    do:
      Tenant.read(
        actor,
        fn a ->
          Repo.all(
            from d in Department, where: d.organization_id == ^a.organization_id, order_by: d.name
          )
        end,
        []
      )

  def admin?(%Membership{} = actor), do: Tenant.read(actor, &(&1.role == "admin"), false)
  def admin?(_), do: false

  def list_staff(actor),
    do:
      Tenant.read(
        actor,
        fn a ->
          if a.role == "admin",
            do:
              Repo.all(
                from m in Membership,
                  where: m.organization_id == ^a.organization_id,
                  preload: [:user, :department],
                  order_by: m.id
              ),
            else: []
        end,
        []
      )

  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: normalize_email(email))

    valid =
      if user, do: Password.valid?(password, user.password_hash), else: Password.dummy_verify()

    if valid and user.active, do: {:ok, user}, else: {:error, :invalid_credentials}
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

  def user_for_token(token) when is_binary(token) and byte_size(token) <= 128 do
    Repo.one(
      from s in Session,
        join: u in assoc(s, :user),
        where: s.token_hash == ^digest(token) and s.expires_at > ^now() and u.active,
        select: u
    )
  end

  def user_for_token(_), do: nil

  def delete_session(token) when is_binary(token) do
    Repo.delete_all(from s in Session, where: s.token_hash == ^digest(token))
    InstantflowWeb.Endpoint.broadcast(socket_id(token), "disconnect", %{})
    :ok
  end

  def delete_session(_), do: :ok
  def socket_id(token), do: "sessions:" <> Base.url_encode64(digest(token), padding: false)

  def invite(actor, attrs) do
    Tenant.transaction(actor, fn a ->
      unless a.role == "admin", do: Repo.rollback(:forbidden)

      department =
        Repo.get_by(Department,
          id: department_id(attrs["department_id"]),
          organization_id: a.organization_id
        )

      unless department, do: Repo.rollback(:invalid_department)
      token = token()

      invitation = %Invitation{
        organization_id: a.organization_id,
        department_id: department.id,
        invited_by_id: a.user_id,
        token_hash: digest(token),
        expires_at: DateTime.add(now(), 172_800)
      }

      case Repo.insert(Invitation.changeset(invitation, attrs)) do
        {:ok, invitation} ->
          audit(
            a.organization_id,
            a.user_id,
            "invitation_created",
            "invitation:#{invitation.id}:created"
          )

          %{invitation: invitation, token: token}

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def accept_invitation(token, attrs, authenticated_user \\ nil)

  def accept_invitation(token, attrs, authenticated_user)
      when is_binary(token) and byte_size(token) <= 128 do
    %{rows: [[id]]} = Repo.query!("SELECT invitation_organization($1)", [digest(token)])

    if id do
      Tenant.raw(id, fn ->
        invitation =
          Repo.one(
            from i in Invitation,
              where: i.organization_id == ^id and i.token_hash == ^digest(token),
              lock: "FOR UPDATE"
          )

        unless invitation && is_nil(invitation.accepted_at) &&
                 DateTime.compare(invitation.expires_at, now()) == :gt,
               do: Repo.rollback(:invalid_invitation)

        existing = Repo.get_by(User, email: invitation.email)

        user =
          cond do
            existing && authenticated_user && existing.id == authenticated_user.id &&
                existing.active ->
              existing

            existing ->
              Repo.rollback(:proof_required)

            true ->
              case Repo.insert(User.changeset(%User{email: invitation.email}, attrs)) do
                {:ok, user} -> user
                {:error, changeset} -> Repo.rollback(changeset)
              end
          end

        # An invitation never upgrades or reactivates an existing membership.
        Repo.insert!(
          %Membership{
            user_id: user.id,
            organization_id: id,
            department_id: invitation.department_id,
            role: invitation.role
          },
          on_conflict: :nothing,
          conflict_target: [:organization_id, :user_id]
        )

        invitation |> Ecto.Changeset.change(accepted_at: now()) |> Repo.update!()
        audit(id, user.id, "invitation_accepted", "invitation:#{invitation.id}:accepted")
        user
      end)
    else
      {:error, :invalid_invitation}
    end
  end

  def accept_invitation(_, _, _), do: {:error, :invalid_invitation}

  def revoke(actor, member_id) do
    result =
      Tenant.transaction(actor, fn a ->
        unless a.role == "admin", do: Repo.rollback(:forbidden)

        member =
          Repo.one(
            from m in Membership,
              where: m.id == ^member_id and m.organization_id == ^a.organization_id,
              lock: "FOR UPDATE"
          )

        unless member && member.id != a.id, do: Repo.rollback(:forbidden)
        result = Repo.update!(Ecto.Changeset.change(member, active: false))

        audit(
          a.organization_id,
          a.user_id,
          "membership_revoked",
          "membership:#{member.id}:#{Ecto.UUID.generate()}"
        )

        result
      end)

    case result do
      {:ok, member} ->
        Phoenix.PubSub.broadcast(
          Instantflow.PubSub,
          "organization:#{member.organization_id}:user:#{member.user_id}",
          :access_revoked
        )

      _ ->
        :ok
    end

    result
  end

  # Called inside the already scoped/locked unit of work; never supplies a fallback organization.
  def lock_scope!(%Membership{} = actor) do
    case scope(actor.user_id, actor.organization_id) do
      nil -> Repo.rollback(:forbidden)
      fresh -> fresh
    end
  end

  def lock_scope!(_), do: Repo.rollback(:forbidden)
  defp token, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  defp audit(organization_id, actor_id, operation, key),
    do:
      Repo.insert!(%Instantflow.Organizations.Event{
        organization_id: organization_id,
        actor_id: actor_id,
        operation: operation,
        key: key
      })

  defp department_id(v) when is_integer(v) and v > 0 and v < 9_223_372_036_854_775_807, do: v

  defp department_id(v) when is_binary(v) do
    case Integer.parse(v) do
      {id, ""} -> department_id(id)
      _ -> -1
    end
  end

  defp department_id(_), do: -1
  defp digest(token), do: :crypto.hash(:sha256, token)
  defp now, do: DateTime.utc_now(:second)
end
