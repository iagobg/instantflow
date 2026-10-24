defmodule Instantflow.WorkflowRuntime.StageBoardsTest do
  use Instantflow.DataCase, async: true
  import Instantflow.WorkflowFixtures
  import Instantflow.IdentityFixtures
  alias Instantflow.{Access, Identity, WorkflowCatalog}
  alias Instantflow.WorkflowCatalog.Views

  test "stage totals authorize before paging and every column has an independent bounded page" do
    f = fixture()
    early = record(f, "Primeira proposta")
    assert {:ok, _} = transition(f.requester, early, "submit")
    drafts = for index <- 1..35, do: record(f, "Proposta #{index}")
    stranger = staff_fixture("staff")
    {:ok, _} = Access.grant(f.admin, stranger.id, stranger.department_id, "teacher")
    stranger = Identity.scope(stranger.user_id, stranger.organization_id)
    for _ <- 1..27, do: record(%{f | requester: stranger}, "Caso oculto")

    result = Views.board(f.requester, f.version.workflow_id, "board", %{})
    assert result.total == 36
    assert result.loaded == 11
    assert Enum.map(result.columns, & &1.id) == Enum.map(f.definition["stages"], & &1["key"])
    assert column(result, "draft").total == 35
    assert length(column(result, "draft").rows) == 10
    assert column(result, "review").rows |> Enum.map(& &1.id) == [early]
    assert column(result, "approved").total == 0
    assert column(result, "approved").rows == []
    assert Enum.all?(result.rows, &(String.starts_with?(&1.title, "Proposta") or &1.id == early))

    last =
      Views.board(f.requester, f.version.workflow_id, "board", %{
        "column_pages" => %{"draft" => "999999999"}
      })

    assert column(last, "draft").page == 4

    assert Enum.map(column(last, "draft").rows, & &1.id) ==
             drafts |> Enum.take(5) |> Enum.reverse()

    assert column(last, "review").rows |> Enum.map(& &1.id) == [early]
    assert last.loaded == 6

    filtered =
      Views.board(f.requester, f.version.workflow_id, "board", %{
        "fields" => %{"request.summary" => "Proposta 1"}
      })

    assert filtered.total == 1
    assert hd(filtered.rows).title == "Proposta 1"
    assert column(filtered, "review").total == 0

    assert Views.board(f.requester, f.version.workflow_id, "board", %{"stage" => "review"}).total ==
             1
  end

  test "an empty current publication still has ordered empty columns and a view entry" do
    f = fixture()

    assert [%{key: "board"}] =
             Views.empty_board_discovery(f.requester, f.version.workflow_id, %{}).rows

    result = Views.board(f.requester, f.version.workflow_id, "board", %{})
    assert result.available?
    assert result.version.id == f.version.id
    assert result.total == 0 and result.loaded == 0
    assert Enum.all?(result.columns, &(&1.total == 0 and &1.rows == []))
    assert Views.board(f.admin, f.version.workflow_id, "board", %{}).version == nil
    assert Views.board(f.requester, nil, "board", %{}).rows == []
  end

  test "incompatible versions never merge labels or cases and archived pins stay accessible" do
    f = fixture()
    old_id = record(f, "Histórico")
    definition = put_in(f.definition, ["stages", Elixir.Access.at(0), "label"], "Recepção nova")
    {:ok, version} = WorkflowCatalog.publish(f.admin, definition, f.bindings, 2)
    result = Views.board(f.requester, version.workflow_id, "board", %{})
    assert result.version.id == version.id
    assert result.total == 0
    assert column(result, "draft").label == "Recepção nova"
    assert Enum.map(result.version_options, & &1.number) == [3, 2]
    new_id = record(%{f | version: version}, "Atual")

    Repo.insert_all("retired_workflow_versions", [
      %{
        version_id: f.version.id,
        organization_id: f.admin.organization_id,
        reason: "Board archive test",
        inserted_at: DateTime.utc_now(:second)
      }
    ])

    old =
      Views.board(f.requester, version.workflow_id, "board", %{
        "version_id" => to_string(f.version.id)
      })

    assert old.version.archived?
    assert old.total == 1 and hd(old.rows).id == old_id
    refute hd(old.rows).id == new_id
    assert column(old, "draft").label != "Recepção nova"

    assert Views.board(f.requester, version.workflow_id, "board", %{"version_id" => "999999"}).version ==
             nil
  end

  test "private fields cannot become card titles, filter values or counts and revoked grants apply immediately" do
    f = Instantflow.CollaborationFixtures.collaborative_fixture()

    definition =
      Map.put(f.definition, "views", [
        %{
          "key" => "board",
          "label" => "Quadro",
          "type" => "board",
          "columns" => ["finance.summary", "request.summary", "stage"],
          "filters" => ["finance.summary", "request.summary"]
        }
      ])

    {:ok, version} = WorkflowCatalog.publish(f.admin, definition, f.bindings, 2)
    f = %{f | version: version}
    id = create_ticket(f)
    assert {:ok, _} = save(f.requester, id, Map.put(values(), "summary", "Título permitido"))
    {:ok, {_, grant}} = Access.grant(f.admin, f.reviewer.id, f.reviewer.department_id, "finance")
    reviewer = Identity.scope(f.reviewer.user_id, f.reviewer.organization_id)

    assert {:ok, _} =
             Instantflow.FinanceFixtures.save(reviewer, id, "finance", %{
               "summary" => "SEGREDO-DO-PARECER"
             })

    result = Views.board(f.requester, version.workflow_id, "board", %{})
    assert hd(result.rows).title == "Título permitido"
    refute Enum.any?(hd(result.rows).cells, &(&1.key == "finance.summary"))
    refute Enum.any?(result.filters, &(&1.ref == "finance.summary"))

    assert Views.board(f.requester, version.workflow_id, "board", %{
             "fields" => %{"finance.summary" => "SEGREDO-DO-PARECER"}
           }).total == 0

    assert hd(Views.board(reviewer, version.workflow_id, "board", %{}).rows).title ==
             "SEGREDO-DO-PARECER"

    assert {:ok, _} = Access.revoke(f.admin, grant.id)

    assert hd(Views.board(reviewer, version.workflow_id, "board", %{}).rows).title ==
             "Título permitido"
  end

  test "stage and version navigation is bounded and preserves explicit historical selection" do
    f = fixture()

    stages =
      for index <- 1..15,
          do: %{
            "key" => "stage#{index}",
            "label" => "Etapa #{index}",
            "initial" => index == 1,
            "terminal" => index == 15
          }

    prototype = hd(f.definition["transitions"])

    edges =
      for index <- 1..14,
          do:
            Map.merge(prototype, %{
              "key" => "next#{index}",
              "from" => "stage#{index}",
              "to" => "stage#{index + 1}",
              "required_fields" => [],
              "actions" => []
            })

    definition =
      f.definition
      |> Map.put("stages", stages)
      |> Map.put("transitions", edges)
      |> Map.update!("sections", fn sections ->
        Enum.map(sections, fn section ->
          Map.update!(section, "access", fn rules ->
            Enum.map(rules, &Map.put(&1, "edit_stages", []))
          end)
        end)
      end)

    {:ok, version} = WorkflowCatalog.publish(f.admin, definition, f.bindings, 2)
    old_id = create_ticket(%{f | version: version})
    first = Views.board(f.requester, version.workflow_id, "board", %{})
    assert length(first.columns) == 10 and first.columns_pages == 2
    last = Views.board(f.requester, version.workflow_id, "board", %{"columns_page" => "999"})
    assert length(last.columns) == 5 and last.columns_page == 2
    assert hd(last.columns).id == "stage11"

    for number <- 4..29 do
      {:ok, next} = WorkflowCatalog.publish(f.admin, definition, f.bindings, number - 1)
      create_ticket(%{f | version: next})
    end

    result =
      Views.board(f.requester, version.workflow_id, "board", %{
        "version_id" => to_string(version.id)
      })

    assert result.version_pages == 2 and result.version_page == 2
    assert result.version.id == version.id and hd(result.rows).id == old_id
    assert Enum.any?(result.version_options, &(&1.id == version.id))
    assert length(result.version_options) <= 25
  end

  test "switching organizations never reveals cases or version options of a foreign board" do
    f = fixture()
    record(f, "Somente Horizonte")

    organization =
      Repo.insert!(%Instantflow.Identity.Organization{slug: "outra", name: "Outra escola"})

    department =
      Repo.insert!(%Instantflow.Identity.Department{
        organization_id: organization.id,
        name: "Equipe"
      })

    Repo.insert!(%Instantflow.Identity.Membership{
      organization_id: organization.id,
      department_id: department.id,
      user_id: f.requester.user_id,
      role: "staff"
    })

    foreign_scope = Identity.scope(f.requester.user_id, organization.id)
    denied = Views.board(foreign_scope, f.version.workflow_id, "board", %{})
    assert denied.rows == [] and denied.total == 0 and denied.version_options == []
  end

  defp fixture do
    f = workflow_fixture()
    {:ok, _} = Access.grant(f.admin, f.requester.id, f.requester.department_id, "teacher")
    {:ok, _} = Access.grant(f.admin, f.reviewer.id, f.reviewer.department_id, "head")

    definition =
      Map.put(f.definition, "views", [
        %{
          "key" => "board",
          "label" => "Quadro de casos",
          "type" => "board",
          "columns" => ["stage", "request.summary"],
          "filters" => ["request.summary"]
        }
      ])

    bindings =
      put_in(f.bindings, ["roles", "requester"], ["teacher"])
      |> put_in(["roles", "reviewer"], ["head"])

    {:ok, version} = WorkflowCatalog.publish(f.admin, definition, bindings, 1)

    %{
      f
      | version: version,
        definition: definition,
        bindings: bindings,
        requester: Identity.scope(f.requester.user_id, f.requester.organization_id),
        reviewer: Identity.scope(f.reviewer.user_id, f.reviewer.organization_id)
    }
  end

  defp record(f, title) do
    id = create_ticket(f)
    assert {:ok, _} = save(f.requester, id, Map.put(values(), "summary", title))
    id
  end

  defp column(board, key), do: Enum.find(board.columns, &(&1.id == key))
end
