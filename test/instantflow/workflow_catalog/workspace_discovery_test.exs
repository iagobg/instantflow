defmodule Instantflow.WorkflowCatalog.WorkspaceDiscoveryTest do
  use Instantflow.DataCase, async: true
  import Instantflow.IdentityFixtures
  alias Instantflow.{Access, BuilderFixtures, WorkflowCatalog}
  alias Instantflow.WorkflowCatalog.{Templates, Workspaces}

  test "targeted lookup and discovery pages fetch bounded authorized definitions before paging" do
    admin = staff_fixture()
    actor = staff_fixture("staff")

    bindings = %{
      "roles" => %{"requester" => ["staff"], "reviewer" => ["admin"]},
      "departments" => %{"responsible" => admin.department_id}
    }

    allowed =
      for n <- 1..55 do
        BuilderFixtures.install(
          admin,
          Templates.starter("visible_#{n}", "Visível #{n}"),
          bindings
        )
      end

    for n <- 1..5 do
      hidden =
        put_in(bindings, ["roles", "requester"], ["external"])
        |> put_in(["roles", "reviewer"], ["external"])

      BuilderFixtures.install(admin, Templates.starter("hidden_#{n}", "Oculto #{n}"), hidden)
    end

    id = List.last(allowed).workflow_id
    handler = "workspace-discovery-#{Ecto.UUID.generate()}"
    :ok = :telemetry.attach(handler, [:instantflow, :repo, :query], &__MODULE__.capture/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)
    assert Workspaces.get(actor, id).workflow_id == id
    rows = events([])
    assert Enum.max(rows) <= 1
    first = Workspaces.search(actor)
    assert first.total == 55 and length(first.rows) == 25
    last = Workspaces.search(actor, %{"page" => "99999"})
    assert last.page == 3 and length(last.rows) == 5
    assert List.last(last.rows).workflow_id == id
    assert Workspaces.search(actor, %{"query" => "Oculto"}).total == 0
    assert Workspaces.search(actor, %{"query" => "Visível 55"}).total == 1
    assert length(WorkflowCatalog.available(actor)) == 25

    assert Enum.map(WorkflowCatalog.available(actor, %{"page" => "3"}), & &1.workflow_id) ==
             Enum.map(last.rows, & &1.workflow_id)

    assert length(Workspaces.navigation(actor)) == 25
    assert Enum.max(events([])) <= 25
  end

  test "historical participant declarations and current grants retain discovery parity" do
    admin = staff_fixture()

    visitor =
      BuilderFixtures.invite_external(admin, "discovery-#{Ecto.UUID.generate()}@example.test")

    bindings = %{
      "roles" => %{"requester" => ["staff"], "reviewer" => ["admin"], "visitor" => ["external"]},
      "departments" => %{"responsible" => admin.department_id}
    }

    original =
      BuilderFixtures.install(admin, BuilderFixtures.participant_page_definition(), bindings)

    {:ok, draft} = Templates.clone(admin, original.id)

    definition =
      put_in(draft.definition, ["interface", "pages"], [
        hd(draft.definition["interface"]["pages"])
      ])

    {:ok, draft} = Templates.save(admin, draft.id, draft.revision, definition, bindings)
    {:ok, latest} = Templates.publish(admin, draft.id, draft.revision)
    assert Workspaces.get(visitor, latest.workflow_id) == nil
    assert Workspaces.installed(visitor) == []
    assert Workspaces.search(visitor).total == 0

    actor = staff_fixture("staff")
    grant_bindings = put_in(bindings, ["roles", "requester"], ["operations"])

    gated =
      BuilderFixtures.install(
        admin,
        Templates.starter("grant_only", "Somente por concessão"),
        Map.update!(grant_bindings, "roles", &Map.delete(&1, "visitor"))
      )

    assert Workspaces.get(actor, gated.workflow_id) == nil
    assert WorkflowCatalog.creatable?(actor, gated.workflow_id) == false
    {:ok, {_, grant}} = Access.grant(admin, actor.id, actor.department_id, "operations")
    assert Workspaces.get(actor, gated.workflow_id).id == gated.id
    assert WorkflowCatalog.creatable?(actor, gated.workflow_id)
    {:ok, _} = Access.revoke(admin, grant.id)
    assert Workspaces.get(actor, gated.workflow_id) == nil
    refute WorkflowCatalog.creatable?(actor, gated.workflow_id)
  end

  def capture(_, _, %{result: {:ok, %{rows: rows}}}, owner)
      when self() == owner and is_list(rows), do: send(owner, {:query_rows, length(rows)})

  def capture(_, _, _, _), do: :ok

  defp events(acc) do
    receive do
      {:query_rows, rows} -> events([rows | acc])
    after
      0 -> acc
    end
  end
end
