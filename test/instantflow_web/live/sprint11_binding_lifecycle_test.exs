defmodule InstantflowWeb.Sprint11BindingLifecycleTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  alias Instantflow.{BuilderFixtures, Finance, FinanceFixtures, Repo, WorkflowRuntime}
  alias Instantflow.WorkflowCatalog.{Authoring, Interchange, Templates, Version}

  test "dependency diagnostics agree across import, draft review and forged publication; retired guardian control is absent" do
    admin = staff_fixture()
    d = Templates.starter("dependency_gate", "Dependência declarada")
    invalid = Map.put(d, "capabilities", ["core", "communications"])

    assert {:error, {:invalid_definition, errors}} =
             Templates.import(admin, Interchange.encode(invalid))

    {:ok, draft} = Templates.import(admin, Interchange.encode(d))
    {:ok, draft} = Templates.save(admin, draft.id, draft.revision, invalid, draft.bindings)
    {:ok, review} = Templates.review(admin, draft.id)
    assert Enum.all?(errors, &(&1 in review.errors))
    {:ok, editor, _} = live(login(build_conn(), admin), "/o/horizonte/modelos/#{draft.id}")
    assert has_element?(editor, "#publication-errors", "modelo.capabilities")
    assert has_element?(editor, "#publish-template[disabled]")
    render_click(editor, "publish", %{})
    assert Repo.aggregate(Version, :count) == 0
    editor |> form("#authoring-picker", picker: %{collection: "transitions"}) |> render_submit()
    editor |> element("#edit-transitions-root-complete") |> render_click()
    refute has_element?(editor, "#item_guardian_roles")
    refute Map.has_key?(Authoring.form().types, :guardian_roles)
  end

  test "republication pins actual finance writes; unavailable bindings fail closed and editor repair is explicit" do
    f = FinanceFixtures.finance_fixture()

    d =
      f.version.definition
      |> Map.put("template_key", "pinned_local_accounts")
      |> Map.put("interface", %{
        "finance" => %{
          "account_binding" => "shared_budget",
          "scope" => "process",
          "view_roles" => ["finance"]
        },
        "pages" => [
          %{
            "key" => "budget",
            "label" => "Orçamento",
            "blocks" => ["records", "finance_setup", "finance_summary"]
          }
        ]
      })

    original = BuilderFixtures.install(f.admin, d, f.version.bindings)
    old_id = FinanceFixtures.request(%{f | version: original}, 3000)

    {:ok, next_account} =
      Finance.create_account(f.admin, f.finance.department_id, "Conta seguinte")

    {:ok, _} =
      Finance.allocate(
        f.finance,
        next_account.id,
        10_000,
        "Dotação sintética",
        Ecto.UUID.generate()
      )

    latest = republish(f.admin, original, next_account.id)
    new_id = FinanceFixtures.request(%{f | version: latest}, 4000)
    assert {:ok, _} = Instantflow.WorkflowFixtures.transition(f.finance, old_id, "reserve")
    assert {:ok, _} = Instantflow.WorkflowFixtures.transition(f.finance, new_id, "reserve")
    assert Repo.get_by!(Instantflow.Finance.Hold, ticket_id: old_id).account_id == f.account.id
    assert Repo.get_by!(Instantflow.Finance.Hold, ticket_id: new_id).account_id == next_account.id
    assert Repo.get!(Instantflow.Finance.Account, f.account.id).reserved == 3000
    assert Repo.get!(Instantflow.Finance.Account, next_account.id).reserved == 4000

    {:ok, unavailable} =
      Finance.create_account(f.admin, f.finance.department_id, "Configuração indisponível")

    broken = republish(f.admin, latest, unavailable.id)
    blocked_id = FinanceFixtures.request(%{f | version: broken}, 1000)
    # Fault injection only: no supported account-archive/delete API exists. A
    # missing local row must still fail closed without rewriting immutable pins.
    Repo.delete!(unavailable)
    {:ok, before} = WorkflowRuntime.get(f.finance, blocked_id)
    before_receipts = Repo.aggregate(Instantflow.WorkflowRuntime.Receipt, :count)
    before_events = Repo.aggregate(Instantflow.WorkflowRuntime.Event, :count)
    before_outbox = Repo.aggregate(Instantflow.Delivery.Message, :count)

    assert {:error, :invalid_budget} =
             Instantflow.WorkflowFixtures.transition(f.finance, blocked_id, "reserve")

    {:ok, after_failure} = WorkflowRuntime.get(f.finance, blocked_id)
    assert before.ticket == after_failure.ticket
    assert Repo.aggregate(Instantflow.WorkflowRuntime.Receipt, :count) == before_receipts
    assert Repo.aggregate(Instantflow.WorkflowRuntime.Event, :count) == before_events
    assert Repo.aggregate(Instantflow.Delivery.Message, :count) == before_outbox
    assert Repo.get_by(Instantflow.Finance.Hold, ticket_id: blocked_id) == nil

    {:ok, workspace, _} =
      live(login(build_conn(), f.finance), "/o/horizonte/processos/#{broken.workflow_id}")

    assert has_element?(workspace, "#process-finance-setup-error[role=alert]", "mapeamento local")
    refute has_element?(workspace, "#process-finance-allocation")
    {:ok, draft} = Templates.clone(f.admin, broken.id)
    {:ok, editor, _} = live(login(build_conn(), f.admin), "/o/horizonte/modelos/#{draft.id}")
    assert has_element?(editor, "#publication-errors", "mapeamentos.budgets.shared_budget")
    assert has_element?(editor, "#publish-template[disabled]")

    editor
    |> form("#template-mappings", mapping: %{budgets: %{shared_budget: next_account.id}})
    |> render_submit()

    refute has_element?(editor, "#publish-template[disabled]")
    editor |> element("#publish-template") |> render_click()
    editor |> element("#confirm-publish-template") |> render_click()
    {:ok, repaired} = Templates.get(f.admin, draft.id)
    assert repaired.published_version_id
    assert Repo.get!(Version, broken.id).bindings["budgets"]["shared_budget"] == unavailable.id

    assert {:error, :invalid_budget} =
             Instantflow.WorkflowFixtures.transition(f.finance, blocked_id, "reserve")

    assert Repo.get_by!(Instantflow.Finance.Hold, ticket_id: old_id).account_id == f.account.id
  end

  defp republish(actor, version, account_id) do
    {:ok, draft} = Templates.clone(actor, version.id)
    bindings = put_in(draft.bindings, ["budgets", "shared_budget"], account_id)
    {:ok, draft} = Templates.save(actor, draft.id, draft.revision, draft.definition, bindings)
    {:ok, version} = Templates.publish(actor, draft.id, draft.revision)
    version
  end
end
