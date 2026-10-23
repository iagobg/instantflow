defmodule InstantflowWeb.Sprint11ProjectionPreviewTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  alias Instantflow.{BuilderFixtures, WorkflowFixtures, WorkflowRuntime}

  test "bounded unicode list previews preserve the complete saved value in generated detail" do
    f = WorkflowFixtures.workflow_fixture()

    d =
      Map.put(f.definition, "views", [
        %{
          "key" => "wide",
          "label" => "Texto",
          "type" => "table",
          "columns" => ["request.justification"]
        }
      ])

    v =
      BuilderFixtures.install(
        f.admin,
        Map.put(d, "template_key", "bounded_text_preview"),
        f.bindings
      )

    id = WorkflowFixtures.create_ticket(%{f | version: v})
    text = String.duplicate("α", 512) <> "FULL_DETAIL_END"

    assert {:ok, _} =
             WorkflowFixtures.save(f.requester, id, %{
               "summary" => "Resumo",
               "justification" => text
             })

    {:ok, page, _} =
      live(login(build_conn(), f.requester), "/o/horizonte/processos/#{v.workflow_id}")

    assert has_element?(page, "#process-record-preview-note")
    assert has_element?(page, "#process-records dd", String.duplicate("α", 80) <> "…")
    refute has_element?(page, "#process-records dd", "FULL_DETAIL_END")
    page |> element("#open-process-record-#{id}") |> render_click()

    {:ok, detail, _} =
      live(
        login(build_conn(), f.requester),
        "/o/horizonte/processos/#{v.workflow_id}/registros/#{id}"
      )

    assert has_element?(
             detail,
             "#section-form-request textarea[name='section[justification]']",
             text
           )

    {:ok, data} = WorkflowRuntime.get(f.requester, id)
    assert Enum.find(data.sections, &(&1.key == "request")).values["justification"] == text
  end
end
