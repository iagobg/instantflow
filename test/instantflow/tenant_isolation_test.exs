defmodule Instantflow.TenantIsolationTest do
  use Instantflow.DataCase, async: true
  import Instantflow.WorkflowFixtures
  alias Instantflow.{Identity, Organizations, Tenant, WorkflowCatalog, WorkflowRuntime, Delivery}
  alias Instantflow.Identity.{Department, Membership, Organization, User}
  alias Instantflow.WorkflowRuntime.{Receipt, Ticket}
  alias Instantflow.Delivery.Message

  defp second_organization(f) do
    org =
      Repo.insert!(%Organization{
        id: System.unique_integer([:positive]) + 1000,
        slug: "aurora-#{System.unique_integer([:positive])}",
        name: "Escola de Teste"
      })

    department = Repo.insert!(%Department{organization_id: org.id, name: "Secretaria"})

    member =
      Repo.insert!(%Membership{
        organization_id: org.id,
        user_id: f.admin.user_id,
        department_id: department.id,
        role: "staff"
      })

    # An independent administrator installs B's own copy; A's admin is only staff in B.
    user =
      Repo.insert!(
        User.changeset(%User{email: "b#{org.id}@escola.example"}, %{
          name: "Administração B",
          password: "fictional-password-123"
        })
      )

    Repo.insert!(%Membership{
      organization_id: org.id,
      user_id: user.id,
      department_id: department.id,
      role: "admin"
    })

    admin = Identity.scope(user.id, org.id)
    scope = Identity.scope(member.user_id, org.id)
    bindings = put_in(f.bindings, ["departments", "review_department"], department.id)
    {:ok, version} = WorkflowCatalog.publish(admin, f.definition, bindings)
    %{organization: org, scope: scope, admin: admin, version: version, department: department}
  end

  test "shared user authority, templates, receipts and guessed IDs remain organization-local" do
    f = workflow_fixture()
    b = second_organization(f)
    assert Identity.admin?(f.admin)
    refute Identity.admin?(%{b.scope | role: "admin"})

    assert {:error, :forbidden} =
             WorkflowCatalog.publish(%{b.scope | role: "admin"}, f.definition, f.bindings)

    a_command = %{
      "operation" => "create",
      "key" => "same-key",
      "workflow_id" => f.version.workflow_id
    }

    b_command = Map.put(a_command, "workflow_id", b.version.workflow_id)
    {:ok, a_result} = WorkflowRuntime.command(f.admin, a_command)
    {:ok, b_result} = WorkflowRuntime.command(b.scope, b_command)
    assert a_result["ticket_id"] != b_result["ticket_id"]
    assert {:ok, ^a_result} = WorkflowRuntime.command(f.admin, a_command)
    assert {:ok, ^b_result} = WorkflowRuntime.command(b.scope, b_command)
    assert {:error, :not_found} = WorkflowRuntime.get(f.admin, b_result["ticket_id"])

    assert {:error, :not_found} =
             WorkflowRuntime.command(f.admin, %{
               "operation" => "create",
               "key" => key(),
               "workflow_id" => b.version.workflow_id
             })

    assert length(Organizations.choices(f.admin.user)) == 2
    assert length(Organizations.choices(f.requester.user)) == 1
    assert Repo.aggregate(Receipt, :count) == 2

    assert Delivery.topic(f.admin.organization_id, 1) !=
             Delivery.topic(b.scope.organization_id, 1)
  end

  test "a shared user's finer grants never combine across organizations" do
    f = Instantflow.CollaborationFixtures.collaborative_fixture()
    b = second_organization(f)

    {:ok, _} =
      Instantflow.Access.grant(
        f.admin,
        f.admin.id,
        f.bindings["departments"]["review_department"],
        "finance"
      )

    {:ok, result} =
      WorkflowRuntime.command(b.scope, %{
        "operation" => "create",
        "key" => key(),
        "workflow_id" => b.version.workflow_id
      })

    forged = %{b.scope | grants: Identity.scope(f.admin.user_id, f.admin.organization_id).grants}
    {:ok, data} = WorkflowRuntime.get(forged, result["ticket_id"])
    refute Enum.any?(data.sections, &(&1.key == "finance"))

    assert {:error, :forbidden} =
             Instantflow.Access.grant(f.admin, b.scope.id, b.department.id, "finance")

    assert {:ok, []} = Tenant.transaction(b.scope, fn _ -> Repo.all(Instantflow.Access.Grant) end)
  end

  test "effective runtime role RLS denies absent/foreign context and pooled scopes reset" do
    f = workflow_fixture()
    b = second_organization(f)
    id = create_ticket(f)

    assert {:ok, {"instantflow_runtime", [^id]}} =
             Tenant.transaction(f.admin, fn _ ->
               user = Repo.query!("SELECT current_user").rows |> hd() |> hd()
               {user, Repo.all(from t in Ticket, select: t.id)}
             end)

    assert {:ok, []} = Tenant.transaction(b.scope, fn _ -> Repo.all(Ticket) end)

    assert {:error, :scope_mismatch} =
             Tenant.transaction(f.admin, fn _ ->
               case Tenant.transaction(b.scope, fn _ -> :not_allowed end) do
                 {:error, reason} -> Repo.rollback(reason)
               end
             end)

    assert Repo.query!("SELECT NULLIF(current_setting('instantflow.organization_id', true), '')").rows ==
             [[nil]]

    Repo.query!("SET LOCAL ROLE instantflow_runtime")
    assert Repo.all(Ticket) == []
  end

  test "raw SQL cross-organization relationships are rejected even when IDs are valid" do
    f = workflow_fixture()
    b = second_organization(f)
    id = create_ticket(f)

    assert_raise Postgrex.Error, fn ->
      Tenant.transaction(b.scope, fn _ ->
        Repo.query!(
          "INSERT INTO ticket_sections (organization_id,ticket_id,key,values,revision,inserted_at,updated_at) VALUES ($1,$2,'forged','{}',1,now(),now())",
          [b.organization.id, id]
        )
      end)
    end
  end

  test "an existing account must prove ownership; invitation acceptance never overwrites credentials or upgrades membership" do
    f = workflow_fixture()
    b = second_organization(f)

    {:ok, result} =
      Identity.invite(b.admin, %{
        "email" => f.requester.user.email,
        "department_id" => b.department.id,
        "role" => "staff"
      })

    old_hash = Repo.get!(User, f.requester.user_id).password_hash

    assert {:error, :proof_required} =
             Identity.accept_invitation(result.token, %{
               "name" => "Forged",
               "password" => "forged-password-123"
             })

    assert Identity.scope(f.requester.user_id, b.organization.id) == nil
    assert {:ok, _} = Identity.accept_invitation(result.token, %{}, f.requester.user)
    assert Repo.get!(User, f.requester.user_id).password_hash == old_hash

    assert {:error, :invalid_invitation} =
             Identity.accept_invitation(result.token, %{}, f.requester.user)

    {:ok, upgrade} =
      Identity.invite(b.admin, %{
        "email" => f.requester.user.email,
        "department_id" => b.department.id,
        "role" => "admin"
      })

    assert {:ok, _} = Identity.accept_invitation(upgrade.token, %{}, f.requester.user)
    assert Identity.scope(f.requester.user_id, b.organization.id).role == "staff"
  end

  test "local revocation leaves global login and the other membership available" do
    f = workflow_fixture()
    b = second_organization(f)
    assert {:ok, _} = Identity.revoke(b.admin, b.scope.id)
    assert Identity.scope(f.admin.user_id, b.organization.id) == nil
    assert Identity.scope(f.admin.user_id, f.admin.organization_id).role == "admin"
    assert {:ok, _} = Identity.authenticate(f.admin.user.email, "fictional-password-123")
  end

  test "worker arguments cannot mix tenants and suspension preserves pending intents" do
    f = workflow_fixture()
    b = second_organization(f)
    id = create_ticket(f)
    message = Repo.get_by!(Message, ticket_id: id)
    assert {:ok, :already_processed} = Delivery.process(b.organization.id, message.id)
    assert Repo.get!(Message, message.id).status == "pending"

    Repo.update!(
      Ecto.Changeset.change(Repo.get!(Organization, f.admin.organization_id), status: "suspended")
    )

    assert {:error, :unavailable} = Delivery.process(f.admin.organization_id, message.id)

    assert {:error, :unavailable} =
             WorkflowRuntime.command(f.admin, %{
               "operation" => "create",
               "key" => key(),
               "workflow_id" => f.version.workflow_id
             })

    assert Identity.scope(f.admin.user_id, f.admin.organization_id) == nil
    assert Identity.scope(f.admin.user_id, b.organization.id)
    assert Repo.get!(Message, message.id).status == "pending"
  end
end
