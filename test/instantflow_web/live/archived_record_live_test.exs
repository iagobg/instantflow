defmodule InstantflowWeb.ArchivedRecordLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  import Instantflow.WorkflowFixtures
  alias Instantflow.{Repo, WorkflowRuntime}

  test "archived resource sessions keep their captured data without operational write controls",
       %{conn: conn} do
    f = Instantflow.OperationsFixtures.operations_fixture()
    id = Instantflow.OperationsFixtures.open_visit(f)
    data = Instantflow.Operations.visit(f.actor, id)

    Repo.insert_all("retired_workflow_versions", [
      %{
        version_id: data.version.id,
        organization_id: f.actor.organization_id,
        reason: "Synthetic operator retirement fixture",
        inserted_at: DateTime.utc_now(:second) |> DateTime.to_naive()
      }
    ])

    {:ok, view, _} =
      live(
        login(conn, f.actor),
        ~p"/o/horizonte/processos/#{data.version.workflow_id}/p/overview/atendimentos/#{id}"
      )

    assert has_element?(view, "#archived-operations")
    assert has_element?(view, "#active-visit", "Carlos")

    for selector <-
          ~w(#product-form #open-visit-form #submit-batch-form #checkout-form #close-day) do
      refute has_element?(view, selector)
    end

    assert Instantflow.WorkflowCatalog.available(f.actor) == []

    assert {:error, :retired_version} =
             Instantflow.Operations.command(f.actor, %{
               "workflow_id" => data.version.workflow_id,
               "operation" => "settle",
               "key" => Ecto.UUID.generate(),
               "session_id" => id,
               "expected_total" => 0,
               "payment_method" => "cash"
             })

    assert Instantflow.Operations.visit(f.actor, id).session == data.session
  end

  test "operator-classified history is readable without mutation or replay controls", %{
    conn: conn
  } do
    f = workflow_fixture()

    command = %{
      "operation" => "create",
      "workflow_id" => f.version.workflow_id,
      "key" => Ecto.UUID.generate()
    }

    {:ok, result} = WorkflowRuntime.command(f.requester, command)
    id = result["ticket_id"]

    Repo.insert_all("retired_workflow_versions", [
      %{
        version_id: f.version.id,
        organization_id: f.admin.organization_id,
        reason: "Synthetic operator retirement fixture",
        inserted_at: DateTime.utc_now(:second) |> DateTime.to_naive()
      }
    ])

    assert {:ok, data} = WorkflowRuntime.get(f.requester, id)
    assert data.archived?
    assert data.editable == []
    assert data.transitions == []
    assert {:error, :retired_version} = WorkflowRuntime.command(f.requester, command)
    outsider = staff_fixture("external")

    forged = %{
      "operation" => "save_section",
      "ticket_id" => id,
      "section" => "request",
      "values" => %{"summary" => "forged"},
      "expected_stage_revision" => 1,
      "expected_section_revision" => 1,
      "key" => Ecto.UUID.generate()
    }

    assert {:error, :forbidden} = WorkflowRuntime.command(outsider, forged)

    assert {:ok, view, _} =
             live(
               login(conn, f.requester),
               ~p"/o/horizonte/processos/#{f.version.workflow_id}/registros/#{id}"
             )

    assert has_element?(view, "#archived-record")
    refute has_element?(view, "#section-form-request")
    refute has_element?(view, "#transition-form")
  end

  test "replacement workspace shows archived unpaid value and offers the released resource", %{
    conn: conn
  } do
    alias Instantflow.{Operations, OperationsFixtures}
    alias Instantflow.WorkflowCatalog.Templates
    f = OperationsFixtures.operations_fixture()
    id = OperationsFixtures.open_visit(f)

    {:ok, %{"ids" => [batch]}} =
      OperationsFixtures.operation(f.actor, "submit_batch", %{
        "session_id" => id,
        "lines" => [OperationsFixtures.item(f.actor, f.soup, 2)]
      })

    visit = Operations.visit(f.actor, id)
    # The populated migration test proves this forward disposition; here verify
    # its generated UI without a privileged runtime or a separate database pool.
    Repo.insert_all("retired_workflow_versions", [
      %{
        version_id: visit.version.id,
        organization_id: f.actor.organization_id,
        reason: "Synthetic migration-result UI fixture",
        inserted_at: DateTime.utc_now(:second) |> DateTime.to_naive()
      }
    ])

    Repo.get!(Instantflow.Operations.Session, id)
    |> Ecto.Changeset.change(status: "archived")
    |> Repo.update!()

    Repo.get!(Instantflow.Operations.Batch, batch)
    |> Ecto.Changeset.change(status: "archived")
    |> Repo.update!()

    {:ok, draft} = Templates.clone(f.actor, visit.version.id)

    {:ok, saved} =
      Templates.save(f.actor, draft.id, draft.revision, draft.definition, draft.bindings)

    {:ok, version} = Templates.publish(f.actor, saved.id, saved.revision)

    {:ok, view, _} =
      live(login(conn, f.actor), ~p"/o/horizonte/processos/#{version.workflow_id}/p/overview")

    assert has_element?(view, "#visit_resource_id option[value='#{f.resource}']")
    assert has_element?(view, "#day-archived", "R$ 51,00")
    assert has_element?(view, "#day-sales", "R$ 0,00")
    refute has_element?(view, "#open-resource-#{f.resource}")
    assert has_element?(view, "#close-day")

    view
    |> form("#open-visit-form",
      visit: %{
        resource_id: to_string(f.resource),
        responsible_actor: "Replacement",
        business_date: Date.to_iso8601(Operations.today(f.actor))
      }
    )
    |> render_submit()

    refute has_element?(view, "#flash-error")
    assert has_element?(view, "#active-visit", "Replacement")
    archived_url = ~p"/o/horizonte/processos/#{version.workflow_id}/p/overview/atendimentos/#{id}"
    {:ok, historical, _} = live(login(build_conn(), f.actor), archived_url)
    assert has_element?(historical, "#visit-archived", "sem quitação")

    assert has_element?(
             historical,
             "#fulfillment-batches",
             "Arquivado sem confirmação de entrega"
           )

    refute has_element?(historical, "#checkout-form")
    refute has_element?(historical, "#handoff-#{batch}")
  end
end
