defmodule Instantflow.WorkflowCatalog.TemplatesTest do
  use Instantflow.DataCase, async: true
  import Instantflow.WorkflowFixtures
  alias Instantflow.{Identity, Tenant, WorkflowRuntime}
  alias Instantflow.WorkflowCatalog.{Draft, Templates, TemplateEvent, Version}
  alias Instantflow.Identity.{Department, Membership, Organization}

  test "cloning, revision checks and publication preserve active version-one requests" do
    f = workflow_fixture()
    ticket_id = create_ticket(f)
    {:ok, draft} = Templates.clone(f.admin, f.version.id)
    definition = Map.put(draft.definition, "name", "Processo revisado")
    {:ok, saved} = Templates.save(f.admin, draft.id, draft.revision, definition, draft.bindings)
    assert saved.revision == 2

    assert {:error, :conflict} =
             Templates.save(f.admin, draft.id, draft.revision, draft.definition, draft.bindings)

    assert {:error, :conflict} = Templates.publish(f.admin, draft.id, draft.revision)
    assert {:ok, review} = Templates.review(f.admin, draft.id)
    assert Enum.any?(review.changes, &(&1.path == "modelo.name"))
    assert review.errors == []

    assert Enum.all?(
             review.roles,
             &(Map.keys(&1) |> Enum.sort() == [:creates?, :id, :label, :sections, :transitions])
           )

    assert {:ok, version} = Templates.publish(f.admin, draft.id, saved.revision)
    assert version.number == 2
    assert {:ok, %{ticket: ticket}} = WorkflowRuntime.get(f.requester, ticket_id)
    assert ticket.workflow_version_id == f.version.id

    assert {:error, :already_published} =
             Templates.save(f.admin, draft.id, saved.revision + 1, definition, draft.bindings)

    assert Repo.aggregate(TemplateEvent, :count) == 3
    event = Repo.get_by!(TemplateEvent, operation: "published")
    assert event.details["bindings"] == draft.bindings
    assert event.actor_id == f.admin.user_id
  end

  test "incomplete graphs can be saved for review but cannot publish" do
    f = workflow_fixture()
    {:ok, draft} = Templates.clone(f.admin, f.version.id)

    orphan = %{
      "key" => "new_stage",
      "label" => "Nova etapa",
      "initial" => false,
      "terminal" => false
    }

    definition = Map.update!(draft.definition, "stages", &(&1 ++ [orphan]))
    {:ok, saved} = Templates.save(f.admin, draft.id, 1, definition, draft.bindings)

    assert {:error, {:invalid_definition, _}} =
             Templates.publish(f.admin, saved.id, saved.revision)

    assert Repo.aggregate(Version, :count) == 1
    assert {:ok, %{errors: [_ | _]}} = Templates.review(f.admin, saved.id)
  end

  test "publishing another draft makes the old draft conflict instead of silently rebasing" do
    f = workflow_fixture()
    {:ok, first} = Templates.clone(f.admin, f.version.id)
    {:ok, second} = Templates.clone(f.admin, f.version.id)
    assert {:ok, _} = Templates.publish(f.admin, first.id, 1)
    assert {:error, :conflict} = Templates.publish(f.admin, second.id, 1)
  end

  test "imports create independent unmapped drafts and have no operational side effects" do
    f = workflow_fixture()
    {:ok, exported} = Templates.export(f.admin, :version, f.version.id)

    before =
      Enum.map(
        [
          Instantflow.WorkflowRuntime.Ticket,
          Instantflow.Delivery.Message,
          Instantflow.Access.Grant,
          Membership
        ],
        &Repo.aggregate(&1, :count)
      )

    assert {:error, :key_taken} = Templates.import(f.admin, exported.json)

    {:ok, draft} =
      Templates.import(f.admin, exported.json, %{"template_key" => "independent_copy"})

    assert draft.workflow_id != f.version.workflow_id
    assert draft.bindings == %{"roles" => %{}, "departments" => %{}}
    assert draft.source_digest == exported.digest
    assert draft.published_version_id == nil
    assert {:error, :invalid_bindings} = Templates.publish(f.admin, draft.id, 1)

    assert before ==
             Enum.map(
               [
                 Instantflow.WorkflowRuntime.Ticket,
                 Instantflow.Delivery.Message,
                 Instantflow.Access.Grant,
                 Membership
               ],
               &Repo.aggregate(&1, :count)
             )

    assert {:ok, imported} =
             Templates.import(f.admin, exported.json, %{"workflow_id" => f.version.workflow_id})

    assert imported.base_version_id == f.version.id
    assert imported.bindings == draft.bindings
    assert {:ok, _} = Templates.save(f.admin, imported.id, 1, imported.definition, f.bindings)
    assert {:ok, _} = Templates.publish(f.admin, imported.id, 2)
  end

  test "shared-user editor access, references, exports and mappings remain organization-local" do
    f = workflow_fixture()

    org =
      Repo.insert!(%Organization{
        id: System.unique_integer([:positive]) + 1000,
        slug: "other-#{System.unique_integer([:positive])}",
        name: "Outra organização"
      })

    department = Repo.insert!(%Department{organization_id: org.id, name: "Operações"})

    Repo.insert!(%Membership{
      organization_id: org.id,
      department_id: department.id,
      user_id: f.admin.user_id,
      role: "admin"
    })

    other = Identity.scope(f.admin.user_id, org.id)
    {:ok, draft} = Templates.clone(f.admin, f.version.id)
    assert {:error, :not_found} = Templates.get(other, draft.id)
    assert {:error, :not_found} = Templates.review(other, draft.id)
    assert {:error, :not_found} = Templates.clone(other, f.version.id)
    assert {:error, :not_found} = Templates.export(other, :version, f.version.id)
    assert {:error, :not_found} = Templates.export(other, :draft, draft.id)

    assert {:error, :not_found} =
             Templates.save(other, draft.id, 1, draft.definition, draft.bindings)

    assert {:error, :not_found} = Templates.publish(other, draft.id, 1)
    invalid = put_in(draft.bindings, ["departments", "review_department"], department.id)

    assert {:error, :invalid_bindings} =
             Templates.save(f.admin, draft.id, 1, draft.definition, invalid)

    assert {:ok, []} = Tenant.transaction(other, fn _ -> Repo.all(Draft) end)
    {:ok, exported} = Templates.export(f.admin, :version, f.version.id)

    assert {:error, :not_found} =
             Templates.import(other, exported.json, %{"workflow_id" => f.version.workflow_id})

    {:ok, copy} = Templates.import(other, exported.json)
    assert copy.organization_id == other.organization_id
    assert copy.definition["template_key"] == f.definition["template_key"]
    assert copy.workflow_id != f.version.workflow_id

    assert {:ok, []} =
             Tenant.transaction(f.admin, fn _ ->
               Repo.all(from d in Draft, where: d.id == ^copy.id)
             end)
  end

  test "forged or revoked administrator scopes cannot use any authoring API" do
    f = workflow_fixture()
    {:ok, draft} = Templates.clone(f.admin, f.version.id)
    forged = %{f.requester | role: "admin"}

    for actor <- [f.requester, forged] do
      assert {:error, :forbidden} = Templates.list(actor)
      assert {:error, :forbidden} = Templates.get(actor, draft.id)
      assert {:error, :forbidden} = Templates.export(actor, :draft, draft.id)
      assert {:error, :forbidden} = Templates.clone(actor, f.version.id)
      assert {:error, :forbidden} = Templates.new(actor, "denied", "Negado")
      assert {:error, :forbidden} = Templates.import(actor, "{}")
      assert {:error, :forbidden} = Templates.publish(actor, draft.id, 1)
    end

    Repo.update_all(from(m in Membership, where: m.id == ^f.admin.id), set: [active: false])

    assert {:error, :forbidden} =
             Templates.save(f.admin, draft.id, 1, draft.definition, draft.bindings)
  end

  test "legacy version spelling normalizes while unsafe historical properties cannot be exported" do
    f = workflow_fixture()
    legacy = Map.put(f.definition, "format_version", "1.0-draft")
    {:ok, version} = Instantflow.WorkflowCatalog.publish(f.admin, legacy, f.bindings, 1)
    {:ok, exported} = Templates.export(f.admin, :version, version.id)
    assert Jason.decode!(exported.json) == Map.put(f.definition, "format_version", "1.0")
    {:ok, draft} = Templates.clone(f.admin, version.id)
    assert draft.definition["format_version"] == "1.0"

    # Prior to Sprint 03, view properties were not structurally checked. Historical rows fail closed.
    unsafe = put_in(legacy, ["views", Access.at(0), "secret"], "fixture-only-secret")

    historical =
      Repo.insert!(%Version{
        organization_id: f.admin.organization_id,
        workflow_id: f.version.workflow_id,
        number: 3,
        definition: unsafe,
        bindings: f.bindings,
        published_by_id: f.admin.user_id
      })

    assert {:error, {:invalid_definition, _}} = Templates.export(f.admin, :version, historical.id)
    assert {:error, {:invalid_definition, _}} = Templates.clone(f.admin, historical.id)
  end
end
