defmodule Instantflow.Finance.SurfacesAndResetsTest do
  use Instantflow.DataCase, async: false
  alias Instantflow.{BuilderFixtures, Finance, FinanceFixtures, WorkflowFixtures, WorkflowRuntime}
  alias Instantflow.WorkflowRuntime.{Section, Event}
  alias Instantflow.WorkflowCatalog.Definition

  test "explicit correction preserves unrelated sections, invalidates approval revisions and rolls back late failure" do
    f = FinanceFixtures.finance_fixture()

    section = fn key, role ->
      %{
        "key" => key,
        "label" => key,
        "classification" => "restricted",
        "access" => [
          %{
            "role" => role,
            "scope" => "assigned_department",
            "read" => true,
            "edit_stages" => ["finance", "purchase"]
          }
        ],
        "fields" => [%{"key" => "note", "label" => "Nota", "type" => "short_text"}]
      }
    end

    definition =
      f.version.definition
      |> Map.put("template_key", "explicit_corrections")
      |> update_in(
        ["sections", Access.at(1), "access", Access.at(3), "edit_stages"],
        &Enum.uniq(["draft" | &1])
      )
      |> Map.update!(
        "sections",
        &(&1 ++ [section.("signoff", "head"), section.("ops_notes", "operations")])
      )
      |> Map.update!("transitions", fn edges ->
        Enum.map(edges, fn edge ->
          if edge["key"] == "revise_purchase",
            do:
              Map.put(edge, "reset", %{
                "sections" => ["order", "delivery"],
                "invalidate_approvals" => ["signoff"]
              }),
            else: edge
        end)
      end)

    version = BuilderFixtures.install(f.admin, definition, f.version.bindings)
    f = %{f | version: version}
    id = FinanceFixtures.request(f)
    assert {:ok, _} = FinanceFixtures.save(f.head, id, "signoff", %{"note" => "APPROVED-PRIVATE"})

    assert {:ok, _} =
             FinanceFixtures.save(f.operations, id, "ops_notes", %{"note" => "PRESERVE-PRIVATE"})

    assert {:ok, _} = WorkflowFixtures.transition(f.finance, id, "reserve")
    before = Repo.all(from s in Section, where: s.ticket_id == ^id) |> Map.new(&{&1.key, &1})
    command = WorkflowFixtures.transition_command(f.operations, id, "revise_purchase", "Revisar")
    previous = Application.get_env(:instantflow, :max_pending_deliveries_per_organization, 1000)

    on_exit(fn ->
      Application.put_env(:instantflow, :max_pending_deliveries_per_organization, previous)
    end)

    Application.put_env(:instantflow, :max_pending_deliveries_per_organization, 0)
    assert {:error, :queue_full} = WorkflowRuntime.command(f.operations, command)
    assert Repo.get!(Section, before["signoff"].id) == before["signoff"]
    assert [%{reserved: 6000}] = Finance.accounts(f.finance)
    Application.put_env(:instantflow, :max_pending_deliveries_per_organization, previous)
    assert {:ok, result} = WorkflowRuntime.command(f.operations, command)
    assert {:ok, ^result} = WorkflowRuntime.command(f.operations, command)
    after_reset = Repo.all(from s in Section, where: s.ticket_id == ^id) |> Map.new(&{&1.key, &1})
    assert after_reset["ops_notes"] == before["ops_notes"]
    assert after_reset["request"] == before["request"]

    assert after_reset["signoff"].values == %{} and
             after_reset["signoff"].revision == before["signoff"].revision + 1

    assert [%{reserved: 0, available: 10000}] = Finance.accounts(f.finance)

    event =
      Repo.one!(from e in Event, where: e.ticket_id == ^id and e.operation == "revise_purchase")

    assert event.details["invalidated_approvals"] == ["signoff"]
    refute inspect(event) =~ "APPROVED-PRIVATE"

    assert {:error, :conflict} =
             WorkflowRuntime.command(f.operations, %{
               "operation" => "save_section",
               "ticket_id" => id,
               "section" => "order",
               "values" => %{},
               "expected_stage_revision" => 4,
               "expected_section_revision" => before["order"].revision,
               "key" => Ecto.UUID.generate()
             })

    invalid =
      put_in(definition, ["transitions", Access.at(0), "reset"], %{
        "sections" => ["unknown"],
        "invalidate_approvals" => []
      })

    assert {:error, _} = Definition.validate(invalid)
  end

  test "process totals are scoped, shared totals require account authority, and rebinding does not move holds" do
    f = FinanceFixtures.finance_fixture()

    configure = fn key, scope ->
      f.version.definition
      |> Map.put("template_key", key)
      |> Map.put("interface", %{
        "finance" => %{
          "account_binding" => "shared_budget",
          "scope" => scope,
          "view_roles" => ["requester"]
        },
        "pages" => [
          %{
            "key" => "budget",
            "label" => "Orçamento",
            "blocks" => ["records", "finance_setup", "finance_summary"]
          }
        ]
      })
    end

    a =
      BuilderFixtures.install(f.admin, configure.("purchase_copy", "process"), f.version.bindings)

    b =
      BuilderFixtures.install(
        f.admin,
        configure.("trip_copy", "shared_account"),
        f.version.bindings
      )

    a_id = FinanceFixtures.request(%{f | version: a}, 3000)
    b_id = FinanceFixtures.request(%{f | version: b}, 4000)
    assert {:ok, _} = WorkflowFixtures.transition(f.finance, a_id, "reserve")
    assert {:ok, _} = WorkflowFixtures.transition(f.finance, b_id, "reserve")

    assert [%{reserved: 3000, available: nil}] =
             Finance.Surfaces.load(f.requester, a.workflow_id).summaries

    assert Finance.Surfaces.load(f.requester, b.workflow_id).summaries == []

    assert {:ok, {_, grant}} =
             Instantflow.Access.grant(
               f.admin,
               f.requester.id,
               f.requester.department_id,
               "finance"
             )

    assert [%{reserved: 7000, available: 3000}] =
             Finance.Surfaces.load(f.requester, b.workflow_id).summaries

    assert {:ok, _} = Instantflow.Access.revoke(f.admin, grant.id)
    assert Finance.Surfaces.load(f.requester, b.workflow_id).summaries == []
    {:ok, account} = Finance.create_account(f.admin, f.finance.department_id, "Nova conta")
    {:ok, draft} = Instantflow.WorkflowCatalog.Templates.clone(f.admin, a.id)
    bindings = put_in(a.bindings, ["budgets", "shared_budget"], account.id)

    {:ok, saved} =
      Instantflow.WorkflowCatalog.Templates.save(
        f.admin,
        draft.id,
        draft.revision,
        a.definition,
        bindings
      )

    assert {:ok, _} =
             Instantflow.WorkflowCatalog.Templates.publish(f.admin, saved.id, saved.revision)

    assert [%{id: account_id, reserved: 3000}] =
             Finance.Surfaces.load(f.requester, a.workflow_id).summaries

    assert account_id == f.account.id
    assert Finance.Surfaces.load(f.finance, a.workflow_id).can_allocate?
    refute Finance.Surfaces.load(f.requester, a.workflow_id).can_allocate?
  end
end
