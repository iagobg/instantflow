defmodule InstantflowWeb.GeneratedProjectionLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  alias Instantflow.{BuilderFixtures, Participants, WorkflowRuntime}
  alias Instantflow.WorkflowCatalog.Templates

  test "a non-creator pages through authorized work and retains pinned views after publication",
       %{conn: conn} do
    admin = staff_fixture()
    clerk = staff_fixture("staff")

    visitor =
      BuilderFixtures.invite_external(admin, "generated-#{Ecto.UUID.generate()}@example.test")

    unrelated =
      BuilderFixtures.invite_external(admin, "generated-#{Ecto.UUID.generate()}@example.test")

    definition =
      BuilderFixtures.participant_definition("customer_repair_inbox")
      |> Map.put("views", [
        %{
          "key" => "my_repairs",
          "label" => "Meus reparos",
          "type" => "table",
          "columns" => ["customer_details.description", "stage"]
        },
        %{
          "key" => "internal_queue",
          "label" => "Fila confidencial",
          "type" => "table",
          "columns" => ["request.summary"]
        }
      ])

    bindings = %{
      "roles" => %{"requester" => ["staff"], "reviewer" => ["admin"], "visitor" => ["external"]},
      "departments" => %{"responsible" => admin.department_id}
    }

    version = BuilderFixtures.install(admin, definition, bindings)

    ids =
      for _ <- 1..26 do
        {:ok, created} =
          WorkflowRuntime.command(clerk, %{
            "operation" => "create",
            "workflow_id" => version.workflow_id,
            "key" => Ecto.UUID.generate()
          })

        id = created["ticket_id"]

        for {operation, revision} <- [{"create", 0}, {"verify", 1}] do
          {:ok, _} =
            Participants.command(
              admin,
              BuilderFixtures.participant_command(id, visitor.id, operation, revision)
            )
        end

        id
      end

    {:ok, created} =
      WorkflowRuntime.command(clerk, %{
        "operation" => "create",
        "workflow_id" => version.workflow_id,
        "key" => Ecto.UUID.generate()
      })

    hidden_id = created["ticket_id"]
    assert Instantflow.WorkflowCatalog.available(visitor) == []
    path = ~p"/o/horizonte/processos/#{version.workflow_id}"
    {:ok, view, _} = live(login(conn, visitor), path)
    refute has_element?(view, "#create-process-record")
    refute has_element?(view, "#record_presentations-internal_queue")
    assert has_element?(view, "#process-record-count", "26")
    assert has_element?(view, "#process-record-page", "1 / 2")
    assert has_element?(view, "#open-process-record-#{List.last(ids)}")
    refute has_element?(view, "#open-process-record-#{hd(ids)}")
    refute has_element?(view, "#open-process-record-#{hidden_id}")

    view |> element("#process-record-next") |> render_click()
    assert has_element?(view, "#process-record-page", "2 / 2")
    assert has_element?(view, "#open-process-record-#{hd(ids)}")
    refute has_element?(view, "#open-process-record-#{List.last(ids)}")

    {:ok, draft} = Templates.clone(admin, version.id)
    revised = Map.put(definition, "views", [])
    {:ok, saved} = Templates.save(admin, draft.id, draft.revision, revised, bindings)
    {:ok, _} = Templates.publish(admin, saved.id, saved.revision)
    {:ok, pinned, _} = live(login(Phoenix.ConnTest.build_conn(), visitor), path)
    assert has_element?(pinned, "#record_presentations-my_repairs")
    assert has_element?(pinned, "#open-process-record-#{List.last(ids)}")

    {:ok, denied, _} = live(login(Phoenix.ConnTest.build_conn(), unrelated), path)
    assert has_element?(denied, "#process-record-count", "0")
    refute has_element?(denied, "#process-record-pagination")
    refute has_element?(denied, "#record_presentations-my_repairs")
    refute has_element?(denied, "#open-process-record-#{List.last(ids)}")
  end
end
