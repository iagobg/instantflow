defmodule Instantflow.Organizations.Operator do
  @moduledoc "Restricted CLI control plane. Requires the separate, unstarted operator repository; no HTTP endpoint."
  import Ecto.Query
  alias Instantflow.OperatorRepo, as: Repo
  alias Instantflow.Identity.{Department, Invitation, Membership, Organization, User}
  alias Instantflow.Organizations.Event

  def provision(operator, slug, name, email, key) do
    email = Instantflow.Identity.normalize_email(email)

    if not Regex.match?(~r/^[a-z][a-z0-9-]{1,62}$/, slug),
      do: raise(ArgumentError, "Slug inválido")

    if not is_binary(operator) or operator == "" or name == "" or key == "",
      do: raise(ArgumentError, "Operador, nome e chave são obrigatórios")

    digest = :crypto.hash(:sha256, :erlang.term_to_binary({slug, name, email})) |> Base.encode16()
    event_key = "provision:#{key}:#{digest}"

    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(98431, hashtext($1))", [key])
      prefix = "provision:#{key}:"

      prior =
        Repo.one(
          from e in Event,
            where: e.operation == "provision" and fragment("starts_with(?, ?)", e.key, ^prefix)
        )

      if prior && prior.key != event_key, do: Repo.rollback(:idempotency_mismatch)
      Repo.query!("SELECT pg_advisory_xact_lock(98432, hashtext($1))", [slug])

      case Repo.get_by(Organization, slug: slug) do
        nil ->
          organization = Repo.insert!(%Organization{slug: slug, name: name})

          department =
            Repo.insert!(%Department{organization_id: organization.id, name: "Administração"})

          system =
            Repo.get_by(User, email: "operator@platform.invalid") ||
              Repo.insert!(%User{
                email: "operator@platform.invalid",
                name: "Operador da plataforma",
                active: false,
                password_hash:
                  Instantflow.Identity.Password.hash(Base.encode64(:crypto.strong_rand_bytes(32)))
              })

          token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
          if system.active, do: Repo.rollback(:reserved_identity_conflict)

          changeset =
            Invitation.changeset(
              %Invitation{
                organization_id: organization.id,
                department_id: department.id,
                invited_by_id: system.id,
                token_hash: :crypto.hash(:sha256, token),
                expires_at: DateTime.add(DateTime.utc_now(:second), 172_800)
              },
              %{"email" => email, "role" => "admin"}
            )

          case Repo.insert(changeset) do
            {:ok, _} -> :ok
            {:error, _} -> Repo.rollback(:invalid_invitation)
          end

          Repo.insert!(%Event{
            organization_id: organization.id,
            operation: "provision",
            operator: operator,
            key: event_key
          })

          %{organization: organization, token: token}

        organization ->
          unless Repo.get_by(Event, organization_id: organization.id, key: event_key),
            do: Repo.rollback(:idempotency_mismatch)

          %{organization: organization, token: nil}
      end
    end)
  end

  def set_status(operator, slug, status, key) when status in ["active", "suspended"] do
    result =
      Repo.transaction(fn ->
        organization =
          Repo.one(from o in Organization, where: o.slug == ^slug, lock: "FOR UPDATE")

        unless organization, do: Repo.rollback(:not_found)

        case Repo.get_by(Event, organization_id: organization.id, key: key) do
          nil ->
            Repo.insert!(%Event{
              organization_id: organization.id,
              operation: status,
              operator: operator,
              key: key
            })

            Repo.update!(Ecto.Changeset.change(organization, status: status))

          event ->
            unless event.operation == status, do: Repo.rollback(:idempotency_mismatch)
            organization
        end
      end)

    case result do
      {:ok, organization} ->
        Phoenix.PubSub.broadcast(
          Instantflow.PubSub,
          "organization:#{organization.id}",
          :access_revoked
        )

      _ ->
        :ok
    end

    result
  end

  def reissue_bootstrap(operator, slug, email, key) do
    if operator == "" or key == "" or byte_size(key) > 128,
      do: raise(ArgumentError, "Operador e chave válidos são obrigatórios")

    email = Instantflow.Identity.normalize_email(email)
    digest = Base.encode16(:crypto.hash(:sha256, email))
    prefix = "bootstrap-reissue:#{key}:"
    event_key = prefix <> digest

    Repo.transaction(fn ->
      organization = Repo.one(from o in Organization, where: o.slug == ^slug, lock: "FOR UPDATE")
      unless organization && organization.status == "active", do: Repo.rollback(:unavailable)

      prior =
        Repo.one(
          from e in Event,
            where:
              e.organization_id == ^organization.id and
                fragment("starts_with(?, ?)", e.key, ^prefix)
        )

      if prior do
        unless prior.key == event_key, do: Repo.rollback(:idempotency_mismatch)
        %{organization: organization, token: nil}
      else
        # Once an administrator membership has existed, ordinary local recovery applies; bootstrap cannot override revocation.
        if Repo.exists?(
             from m in Membership,
               where: m.organization_id == ^organization.id and m.role == "admin"
           ),
           do: Repo.rollback(:already_bootstrapped)

        department =
          Repo.one!(
            from d in Department,
              where: d.organization_id == ^organization.id,
              order_by: d.id,
              limit: 1
          )

        system = Repo.get_by!(User, email: "operator@platform.invalid")
        token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

        changeset =
          Invitation.changeset(
            %Invitation{
              organization_id: organization.id,
              department_id: department.id,
              invited_by_id: system.id,
              token_hash: :crypto.hash(:sha256, token),
              expires_at: DateTime.add(DateTime.utc_now(:second), 172_800)
            },
            %{"email" => email, "role" => "admin"}
          )

        case Repo.insert(changeset) do
          {:ok, invitation} ->
            Repo.update_all(
              from(i in Invitation,
                where:
                  i.organization_id == ^organization.id and i.id != ^invitation.id and
                    is_nil(i.accepted_at) and i.role == "admin"
              ),
              set: [expires_at: DateTime.utc_now(:second)]
            )

          {:error, _} ->
            Repo.rollback(:invalid_invitation)
        end

        Repo.insert!(%Event{
          organization_id: organization.id,
          operation: "bootstrap_reissued",
          operator: operator,
          key: event_key
        })

        %{organization: organization, token: token}
      end
    end)
  end
end
