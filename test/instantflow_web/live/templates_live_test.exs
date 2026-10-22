defmodule InstantflowWeb.TemplatesLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  import Instantflow.WorkflowFixtures
  alias Instantflow.{Repo, WorkflowCatalog.Templates}
  alias Instantflow.WorkflowCatalog.{Draft, Version}

  test "administrator creates a process, adds typed fields and publishes through keyboard forms",
       %{conn: conn} do
    admin = staff_fixture()
    conn = login(conn, admin)
    {:ok, list, _} = live(conn, ~p"/o/horizonte/modelos")

    list
    |> form("#new-workflow-form", workflow: %{key: "office", name: "Processo de escritório"})
    |> render_submit()

    draft = Repo.one!(Draft)
    assert_redirect(list, "/o/horizonte/modelos/#{draft.id}")
    {:ok, editor, _} = live(conn, ~p"/o/horizonte/modelos/#{draft.id}")
    assert has_element?(editor, "#workflow-graph")
    assert has_element?(editor, "#role-preview")
    assert has_element?(editor, "#publish-template[disabled]")

    editor
    |> form("#authoring-picker", picker: %{collection: "fields", section: "request"})
    |> render_submit()

    editor
    |> form("#template-item-form",
      item: %{key: "cost", label: "Custo previsto", type: "money", currency: "BRL"}
    )
    |> render_submit()

    assert has_element?(editor, "#items-fields-request-cost")
    assert has_element?(editor, "#item_key[value='cost'][readonly]")
    assert has_element?(editor, "#item_type option[value='money'][selected]")

    editor
    |> form("#template-mappings",
      mapping: %{
        roles: %{requester: ["staff"], reviewer: ["admin"]},
        departments: %{responsible: admin.department_id},
        assignment: "responsible"
      }
    )
    |> render_submit()

    refute has_element?(editor, "#publish-template[disabled]")
    editor |> element("#publish-template") |> render_click()
    assert Repo.aggregate(Version, :count) == 1
    assert has_element?(editor, "#save-template-item[disabled]")
    editor |> element("#export-draft") |> render_click()
    assert has_element?(editor, "#draft-export-preview")
    assert has_element?(editor, "#download-draft[download='modelo-rascunho.json']")
  end

  test "cloning, comparison and conflicting saves preserve the losing editor's input", %{
    conn: conn
  } do
    f = workflow_fixture()
    {:ok, draft} = Templates.clone(f.admin, f.version.id)
    conn = login(conn, f.admin)
    {:ok, first, _} = live(conn, ~p"/o/horizonte/modelos/#{draft.id}")
    {:ok, second, _} = live(conn, ~p"/o/horizonte/modelos/#{draft.id}")
    first |> form("#template-metadata", metadata: %{name: "Primeira edição"}) |> render_submit()
    second |> form("#template-metadata", metadata: %{name: "Segunda edição"}) |> render_submit()
    assert has_element?(second, "#draft-conflict")
    assert has_element?(second, "#conflict-local-json", "Segunda edição")
    assert has_element?(second, "#conflict-diff")
    assert {:ok, saved} = Templates.get(f.admin, draft.id)
    assert saved.definition["name"] == "Primeira edição"
    second |> element("#reload-draft") |> render_click()
    refute has_element?(second, "#draft-conflict")
    assert has_element?(second, "#template-diff")
    assert has_element?(second, "#metadata_name[value='Primeira edição']")
  end

  test "imports remain drafts, labels are escaped and export is a reviewed explicit action", %{
    conn: conn
  } do
    f = workflow_fixture()
    {:ok, exported} = Templates.export(f.admin, :version, f.version.id)
    {:ok, list, _} = live(login(conn, f.admin), ~p"/o/horizonte/modelos")
    list |> element("#export-version-#{f.version.id}") |> render_click()
    assert has_element?(list, "#export-preview")

    list
    |> form("#import-template-form", import: %{json: exported.json, key: "new_copy"})
    |> render_submit()

    draft = Repo.one!(Draft)
    assert_redirect(list, "/o/horizonte/modelos/#{draft.id}")
    assert draft.published_version_id == nil
    assert draft.bindings == %{"roles" => %{}, "departments" => %{}}
    assert Repo.aggregate(Version, :count) == 1
  end

  test "stage focus highlights its connections without changing the draft or clearing unsaved edits",
       %{conn: conn} do
    f = workflow_fixture()
    {:ok, draft} = Templates.clone(f.admin, f.version.id)
    {:ok, editor, _} = live(login(conn, f.admin), ~p"/o/horizonte/modelos/#{draft.id}")
    editor |> form("#template-metadata", metadata: %{name: "Edição pendente"}) |> render_change()
    editor |> form("#graph-focus-form", graph: %{stage: "review"}) |> render_change()
    assert has_element?(editor, "#graph-nodes .focused")
    assert has_element?(editor, "#graph-edges .dimmed")
    assert has_element?(editor, "#publish-template[disabled]")
    assert {:ok, %{revision: 1}} = Templates.get(f.admin, draft.id)
    editor |> form("#graph-focus-form", graph: %{stage: ""}) |> render_change()
    refute has_element?(editor, "#graph-edges .dimmed")
  end

  test "administrator declares a participant relationship through typed editor controls", %{
    conn: conn
  } do
    admin = staff_fixture()
    {:ok, draft} = Templates.new(admin, "external_service", "Serviço externo")
    {:ok, editor, _} = live(login(conn, admin), ~p"/o/horizonte/modelos/#{draft.id}")
    editor |> form("#authoring-picker", picker: %{collection: "participants"}) |> render_submit()

    editor
    |> form("#template-item-form",
      item: %{
        key: "customer",
        label: "Cliente verificado",
        kind: "external",
        candidate_roles: ["requester"],
        manager_roles: ["reviewer"],
        department_binding: "responsible"
      }
    )
    |> render_submit()

    assert has_element?(editor, "#items-participants-root-customer")
    {:ok, saved} = Templates.get(admin, draft.id)

    assert saved.definition["participants"] == [
             %{
               "key" => "customer",
               "label" => "Cliente verificado",
               "kind" => "external",
               "candidate_roles" => ["requester"],
               "managers" => [
                 %{
                   "role" => "reviewer",
                   "scope" => "workflow_department",
                   "department_binding" => "responsible"
                 }
               ]
             }
           ]

    assert "participants" in saved.definition["capabilities"]

    editor
    |> form("#authoring-picker", picker: %{collection: "access", section: "request"})
    |> render_submit()

    editor
    |> form("#template-item-form",
      item: %{
        role: "requester",
        scope: "participant",
        relationship: "customer",
        read: true,
        edit_stages: ["draft"]
      }
    )
    |> render_submit()

    assert has_element?(editor, "#items-access-request-requester-participant-customer")

    editor
    |> form("#authoring-picker", picker: %{collection: "fields", section: "request"})
    |> render_submit()

    editor
    |> form("#template-item-form",
      item: %{
        key: "contact",
        label: "Contato",
        type: "directory_reference",
        reference_target: "participant",
        reference_relationship: "customer"
      }
    )
    |> render_submit()

    assert has_element?(editor, "#items-fields-request-contact")
    {:ok, configured} = Templates.get(admin, draft.id)
    field = Enum.find(hd(configured.definition["sections"])["fields"], &(&1["key"] == "contact"))

    assert field["reference"] == %{
             "target" => "participant",
             "relationship" => "customer",
             "cardinality" => "one"
           }

    editor
    |> form("#authoring-picker", picker: %{collection: "fields", section: "request"})
    |> render_submit()

    editor
    |> form("#template-item-form",
      item: %{
        key: "evidence",
        label: "Comprovante",
        type: "attachment",
        document_reviewers: ["reviewer"],
        document_department: "responsible",
        document_max_bytes: "4096",
        document_media_types: ["application/pdf"]
      }
    )
    |> render_submit()

    assert has_element?(editor, "#items-fields-request-evidence")
    {:ok, documents} = Templates.get(admin, draft.id)
    assert "documents" in documents.definition["capabilities"]

    editor
    |> form("#interface-page-form",
      interface_page: %{
        key: "overview",
        label: "Trabalho",
        blocks: ["records", "catalog"],
        close_transition: "complete"
      }
    )
    |> render_submit()

    {:ok, composed} = Templates.get(admin, draft.id)
    assert "participants" in composed.definition["capabilities"]
    assert "operations" in composed.definition["capabilities"]
  end

  test "non-administrators and revoked sessions cannot author or export", %{conn: conn} do
    staff = staff_fixture("staff")

    assert {:error, {:live_redirect, %{to: "/o/horizonte"}}} =
             live(login(conn, staff), ~p"/o/horizonte/modelos")

    admin = staff_fixture()
    token = Instantflow.Identity.create_session(admin.user)

    {:ok, list, _} =
      live(Plug.Test.init_test_session(conn, user_token: token), ~p"/o/horizonte/modelos")

    Instantflow.Identity.delete_session(token)

    list
    |> form("#new-workflow-form", workflow: %{key: "denied", name: "Negado"})
    |> render_submit()

    assert_redirect(list, "/organizacoes")
    assert Repo.aggregate(Draft, :count) == 0
  end

  test "JSON file upload creates a draft and imported labels stay escaped", %{conn: conn} do
    admin = staff_fixture()

    json =
      Instantflow.WorkflowCatalog.Templates.starter("uploaded", "<script>unsafe()</script>")
      |> Jason.encode!()

    {:ok, list, _} = live(login(conn, admin), ~p"/o/horizonte/modelos")

    upload =
      file_input(list, "#import-template-form", :template, [
        %{name: "process.json", content: json, type: "application/json"}
      ])

    render_upload(upload, "process.json")
    list |> form("#import-template-form", import: %{}) |> render_submit()
    draft = Repo.one!(Draft)
    assert_redirect(list, "/o/horizonte/modelos/#{draft.id}")
    {:ok, editor, _} = live(login(conn, admin), ~p"/o/horizonte/modelos/#{draft.id}")
    assert has_element?(editor, "#workflow-editor h1", "<script>unsafe()</script>")
    refute has_element?(editor, "#workflow-editor h1 script")
    assert has_element?(editor, "#publish-template[disabled]")
  end

  test "authored multiple-choice and date/time fields save through ordinary request forms", %{
    conn: conn
  } do
    f = workflow_fixture()
    {:ok, draft} = Templates.clone(f.admin, f.version.id)

    fields = [
      %{
        "key" => "tags",
        "label" => "Marcadores",
        "type" => "multiple_choice",
        "options" => ["A", "B"]
      },
      %{"key" => "scheduled_at", "label" => "Agendamento", "type" => "datetime"}
    ]

    definition =
      Map.update!(draft.definition, "sections", fn [section] ->
        [Map.update!(section, "fields", &(&1 ++ fields))]
      end)

    {:ok, saved} = Templates.save(f.admin, draft.id, 1, definition, draft.bindings)
    {:ok, version} = Templates.publish(f.admin, saved.id, saved.revision)
    ticket = create_ticket(%{f | version: version})
    {:ok, view, _} = live(login(conn, f.requester), ~p"/o/horizonte/solicitacoes/#{ticket}")
    assert has_element?(view, "#section-request-tags[multiple]")

    view
    |> form("#section-form-request",
      section: %{
        summary: "Teste",
        justification: "Fictício",
        tags: ["A", "B"],
        scheduled_at: "2026-10-20T14:00:00-03:00"
      }
    )
    |> render_submit()

    {:ok, data} = Instantflow.WorkflowRuntime.get(f.requester, ticket)
    [section] = data.sections
    assert section.values["tags"] == ["A", "B"]
    assert section.values["scheduled_at"] == "2026-10-20T14:00:00-03:00"
    view |> form("#section-form-request", section: %{tags: []}) |> render_submit()
    {:ok, %{sections: [section]}} = Instantflow.WorkflowRuntime.get(f.requester, ticket)
    assert section.values["tags"] == []
  end
end
