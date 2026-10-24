defmodule InstantflowWeb.StageBoardLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.WorkflowFixtures
  import Instantflow.IdentityFixtures
  alias Instantflow.{Access, Delivery, Repo, WorkflowCatalog, WorkflowRuntime}
  alias Instantflow.FinanceFixtures

  test "ordered columns retain empty stages and page cards independently beyond the global first 25",
       %{conn: conn} do
    f = board_fixture()
    early = create_ticket(f)
    assert {:ok, _} = save(f.requester, early, values())
    assert {:ok, _} = transition(f.requester, early, "submit")

    drafts =
      for index <- 1..32 do
        id = create_ticket(f)
        assert {:ok, _} = save(f.requester, id, Map.put(values(), "summary", "Proposta #{index}"))
        id
      end

    {:ok, board, _} =
      live(login(conn, f.requester), ~p"/o/horizonte/processos/#{f.version.workflow_id}")

    assert has_element?(board, "#board-version[data-version-id='#{f.version.id}']")
    assert has_element?(board, "#board-count-draft", "10 exibidos de 32")
    assert has_element?(board, "#board-count-review", "1 exibidos de 1")
    assert has_element?(board, "#board-empty-approved")
    assert has_element?(board, "#board-column-review #open-process-record-#{early}")
    refute has_element?(board, "#board-column-draft #open-process-record-#{hd(drafts)}")
    for _ <- 1..3, do: board |> element("#board-next-draft") |> render_click()
    assert has_element?(board, "#board-count-draft", "2 exibidos de 32")
    assert has_element?(board, "#board-column-draft #open-process-record-#{hd(drafts)}")
    assert has_element?(board, "#board-column-review #open-process-record-#{early}")
    refute has_element?(board, "#process-record-pagination")
    assert has_element?(board, "#board-column-draft h5", "Proposta 1")

    board
    |> form("#process-record-filters",
      record_filter: %{view: "board", fields: %{"request.summary" => "Proposta 1"}}
    )
    |> render_submit()

    assert has_element?(board, "#board-count-draft", "1 exibidos de 1")
    assert has_element?(board, "#board-empty-review")
    assert has_element?(board, "#open-process-record-#{hd(drafts)}")
    refute has_element?(board, "#open-process-record-#{early}")
  end

  test "other users' permitted transitions and corrections refresh both boards while denials cannot mutate",
       %{conn: conn} do
    f = FinanceFixtures.finance_fixture()
    id = FinanceFixtures.request(f)

    {:ok, board, _} =
      live(login(conn, f.requester), ~p"/o/horizonte/processos/#{f.version.workflow_id}")

    board |> form("#process-record-filters", record_filter: %{view: "board"}) |> render_submit()

    {:ok, peer, _} =
      live(
        login(Phoenix.ConnTest.build_conn(), f.finance),
        ~p"/o/horizonte/processos/#{f.version.workflow_id}"
      )

    peer |> form("#process-record-filters", record_filter: %{view: "board"}) |> render_submit()

    board
    |> form("#process-record-filters", record_filter: %{view: "board", query: to_string(id)})
    |> render_submit()

    assert has_element?(board, "#board-column-finance #open-process-record-#{id}")
    {:ok, before} = WorkflowRuntime.get(f.requester, id)
    assert {:error, :forbidden} = transition(f.requester, id, "reserve")
    {:ok, unchanged} = WorkflowRuntime.get(f.requester, id)
    assert unchanged.ticket.revision == before.ticket.revision
    assert {:ok, _} = transition(f.finance, id, "reserve")
    Delivery.drain()

    for view <- [board, peer] do
      assert has_element?(view, "#board-column-purchase #open-process-record-#{id}")
      assert has_element?(view, "#board-empty-finance")
      refute has_element?(view, "#board-column-finance #open-process-record-#{id}")
    end

    assert has_element?(board, "#record_filter_query[value='#{id}']")
    assert {:ok, _} = transition(f.operations, id, "revise_purchase", "Rever proposta fictícia")
    Delivery.drain()

    for view <- [board, peer] do
      assert has_element?(view, "#board-column-draft #open-process-record-#{id}")
      assert has_element?(view, "#board-empty-purchase")
    end

    assert has_element?(board, "#record_filter_query[value='#{id}']")

    assert has_element?(
             board,
             "#board-column-draft #open-process-record-#{id}[href='/o/horizonte/processos/#{f.version.workflow_id}/registros/#{id}']"
           )
  end

  test "version changes replace streams and publication does not silently switch an older selected board",
       %{conn: conn} do
    f = board_fixture()
    old = create_ticket(f)
    definition = put_in(f.definition, ["stages", Elixir.Access.at(0), "label"], "Recepção nova")
    {:ok, version} = WorkflowCatalog.publish(f.admin, definition, f.bindings, 2)
    current = create_ticket(%{f | version: version})

    {:ok, board, _} =
      live(login(conn, f.requester), ~p"/o/horizonte/processos/#{version.workflow_id}")

    assert has_element?(board, "#board-column-draft h4", "Recepção nova")
    assert has_element?(board, "#open-process-record-#{current}")
    refute has_element?(board, "#open-process-record-#{old}")

    board
    |> form("#process-record-filters",
      record_filter: %{view: "board", version_id: to_string(f.version.id)}
    )
    |> render_submit()

    assert has_element?(
             board,
             "#board-version[data-version-id='#{f.version.id}']",
             "Publicação anterior"
           )

    assert has_element?(board, "#open-process-record-#{old}")
    refute has_element?(board, "#open-process-record-#{current}")
    refute has_element?(board, "#board-column-draft h4", "Recepção nova")
    assert {:ok, _} = WorkflowCatalog.publish(f.admin, definition, f.bindings, 3)
    assert has_element?(board, "#board-version[data-version-id='#{f.version.id}']")
    assert has_element?(board, "#open-process-record-#{old}")
    refute has_element?(board, "#open-process-record-#{current}")
  end

  test "empty published boards are available and revoked access removes cards and version metadata",
       %{conn: conn} do
    f = FinanceFixtures.finance_fixture()

    {:ok, board, _} =
      live(login(conn, f.requester), ~p"/o/horizonte/processos/#{f.version.workflow_id}")

    assert has_element?(board, "#board-empty-draft")
    assert has_element?(board, "#board-empty-complete")
    id = FinanceFixtures.request(f)
    Delivery.drain()
    assert has_element?(board, "#open-process-record-#{id}")
    grant = Repo.get_by!(Access.Grant, membership_id: f.requester.id, role: "teacher")
    assert {:ok, _} = Access.revoke(f.admin, grant.id)
    assert_redirect(board, ~p"/o/horizonte/processos")

    denied =
      Instantflow.WorkflowCatalog.Views.board(f.requester, f.version.workflow_id, "board", %{})

    assert denied.rows == [] and denied.version_options == [] and denied.version == nil
  end

  test "large definitions page their stage window without leaving cards from the previous window",
       %{conn: conn} do
    f = board_fixture()

    stages =
      for index <- 1..15,
          do: %{
            "key" => "stage#{index}",
            "label" => "Etapa #{index}",
            "initial" => index == 1,
            "terminal" => index == 15
          }

    prototype = hd(f.definition["transitions"])

    transitions =
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
      |> Map.put("transitions", transitions)
      |> Map.update!("sections", fn sections ->
        Enum.map(sections, fn section ->
          Map.update!(section, "access", fn rules ->
            Enum.map(rules, &Map.put(&1, "edit_stages", []))
          end)
        end)
      end)

    {:ok, version} = WorkflowCatalog.publish(f.admin, definition, f.bindings, 2)
    id = create_ticket(%{f | version: version})

    {:ok, board, _} =
      live(login(conn, f.requester), ~p"/o/horizonte/processos/#{version.workflow_id}")

    assert has_element?(board, "#board-column-stage1 #open-process-record-#{id}")
    refute has_element?(board, "#board-column-stage11")
    board |> element("#board-columns-next") |> render_click()
    assert has_element?(board, "#board-empty-stage11")
    assert has_element?(board, "#board-empty-stage15")
    refute has_element?(board, "#board-column-stage1")
    refute has_element?(board, "#open-process-record-#{id}")
    board |> element("#board-columns-previous") |> render_click()
    assert has_element?(board, "#board-column-stage1 #open-process-record-#{id}")
    refute has_element?(board, "#board-column-stage11")
  end

  test "authorized historical boards remain reachable when current role mappings remove workspace access",
       %{conn: conn} do
    f = FinanceFixtures.finance_fixture()
    id = FinanceFixtures.request(f)
    new_bindings = put_in(f.version.bindings, ["roles", "requester"], ["it"])
    {:ok, _} = WorkflowCatalog.publish(f.admin, f.version.definition, new_bindings, 1)
    assert Instantflow.WorkflowCatalog.Workspaces.get(f.requester, f.version.workflow_id) == nil

    {:ok, board, _} =
      live(login(conn, f.requester), ~p"/o/horizonte/processos/#{f.version.workflow_id}")

    board |> form("#process-record-filters", record_filter: %{view: "board"}) |> render_submit()

    assert has_element?(
             board,
             "#board-version[data-version-id='#{f.version.id}']",
             "Publicação anterior"
           )

    assert has_element?(board, "#board-column-finance #open-process-record-#{id}")
    refute has_element?(board, "#create-process-record")
    refute has_element?(board, "#process-flow-link")
  end

  test "the global board chooser opens the shared version-aware process board", %{conn: conn} do
    f = board_fixture()
    id = create_ticket(f)
    conn = login(conn, f.requester)
    {:ok, requests, _} = live(conn, ~p"/o/horizonte/solicitacoes")

    requests
    |> form("#configured-view-form", view: %{key: "#{f.version.workflow_id}:board"})
    |> render_submit()

    assert_redirect(requests, ~p"/o/horizonte/processos/#{f.version.workflow_id}?view=board")
    {:ok, board, _} = live(conn, ~p"/o/horizonte/processos/#{f.version.workflow_id}?view=board")
    assert has_element?(board, "#board-column-draft #open-process-record-#{id}")
    refute has_element?(board, "#configured-board-rows")
  end

  defp board_fixture do
    f = workflow_fixture()

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

    {:ok, version} = WorkflowCatalog.publish(f.admin, definition, f.bindings, 1)
    %{f | definition: definition, version: version}
  end
end
