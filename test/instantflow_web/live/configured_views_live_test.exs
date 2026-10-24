defmodule InstantflowWeb.ConfiguredViewsLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  import Instantflow.WorkflowFixtures
  alias Instantflow.{Repo, WorkflowCatalog.Templates}

  test "typed view authoring publishes bounded filters and generated pages operate them", %{
    conn: conn
  } do
    f = workflow_fixture()
    {:ok, draft} = Templates.clone(f.admin, f.version.id)
    {:ok, editor, _} = live(login(conn, f.admin), ~p"/o/horizonte/modelos/#{draft.id}")
    editor |> form("#authoring-picker", picker: %{collection: "views"}) |> render_submit()

    editor
    |> form("#template-item-form",
      item: %{
        key: "scoped",
        label: "Fila configurada",
        type: "board",
        columns: ["stage", "request.summary"],
        view_filters: ["request.summary"],
        visibility_roles: ["requester", "reviewer"],
        sort_field: "request.summary",
        sort_direction: "asc"
      }
    )
    |> render_submit()

    refute has_element?(editor, "#publish-template[disabled]")
    editor |> element("#publish-template") |> render_click()
    editor |> element("#confirm-publish-template") |> render_click()
    {:ok, published} = Templates.get(f.admin, draft.id)
    version = Repo.get!(Instantflow.WorkflowCatalog.Version, published.published_version_id)
    f = %{f | version: version}
    a = create_ticket(f)
    b = create_ticket(f)
    assert {:ok, _} = save(f.requester, a, Map.put(values(), "summary", "Alfa"))
    assert {:ok, _} = save(f.requester, b, Map.put(values(), "summary", "Zeta"))

    {:ok, process, _} =
      live(
        login(Phoenix.ConnTest.build_conn(), f.requester),
        ~p"/o/horizonte/processos/#{version.workflow_id}"
      )

    process
    |> form("#process-record-filters", record_filter: %{view: "scoped"})
    |> render_submit()

    assert has_element?(process, "[id='record-filter-request.summary'] option[value='Alfa']")

    process
    |> form("#process-record-filters",
      record_filter: %{view: "scoped", fields: %{"request.summary" => "Alfa"}}
    )
    |> render_submit()

    assert has_element?(process, "#open-process-record-#{a}")
    refute has_element?(process, "#open-process-record-#{b}")
  end
end
