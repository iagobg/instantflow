defmodule InstantflowWeb.ParticipantDirectoryLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  alias Instantflow.{BuilderFixtures, Participants, WorkflowRuntime}

  test "subject-only eligibility supports linking and references without granting record access",
       %{conn: conn} do
    admin = staff_fixture()
    clerk = staff_fixture("staff")

    subject =
      BuilderFixtures.invite_external(
        admin,
        "subject-#{System.unique_integer([:positive])}@example.test"
      )

    definition =
      BuilderFixtures.directory_definition("subject_only")
      |> Map.update!("sections", &Enum.reject(&1, fn s -> s["key"] == "customer_details" end))
      |> put_in(["participants", Access.at(0), "kind"], "subject")
      |> put_in(
        ["sections", Access.at(0), "fields", Access.at(1), "reference", "target"],
        "subject"
      )

    version =
      BuilderFixtures.install(admin, definition, %{
        "roles" => %{"requester" => ["staff"], "reviewer" => ["admin"], "visitor" => ["external"]},
        "departments" => %{"responsible" => admin.department_id}
      })

    {:ok, result} =
      WorkflowRuntime.command(clerk, %{
        "operation" => "create",
        "workflow_id" => version.workflow_id,
        "key" => Ecto.UUID.generate()
      })

    id = result["ticket_id"]

    {:ok, view, _} =
      live(login(conn, admin), ~p"/o/horizonte/processos/#{version.workflow_id}/registros/#{id}")

    view
    |> form("#participant-search-form", participant_search: %{query: subject.user.email})
    |> render_change()

    assert has_element?(view, "#participant-add-claimant option[value='#{subject.id}']")
    refute has_element?(view, "#participant-add-claimant option[value='#{clerk.id}']")

    view
    |> form("#participant-add-claimant", participant: %{membership_id: to_string(subject.id)})
    |> render_submit()

    [relationship] = Participants.controls(admin, id).relationships
    view |> element("#participant-verify-#{relationship.id}") |> render_click()
    assert has_element?(view, "#section-request-contact option[value='#{relationship.id}']")

    view
    |> form("#section-form-request",
      section: %{summary: "Sujeito sem acesso", contact: to_string(relationship.id)}
    )
    |> render_submit()

    {:ok, data} = WorkflowRuntime.get(admin, id)
    assert hd(data.sections).values["contact"] == relationship.id
    assert {:error, :not_found} = WorkflowRuntime.get(subject, id)
    assert WorkflowRuntime.search(subject).total == 0
    assert Participants.controls(subject, id).controls == []
  end

  test "generated record forms search, save and invalidate a scoped directory selection", %{
    conn: conn
  } do
    admin = staff_fixture()
    clerk = staff_fixture("staff")
    visitor = staff_fixture("parent")
    unrelated = staff_fixture("parent")
    definition = BuilderFixtures.directory_definition()

    bindings = %{
      "roles" => %{"requester" => ["staff"], "reviewer" => ["admin"], "visitor" => ["parent"]},
      "departments" => %{"responsible" => admin.department_id}
    }

    version = BuilderFixtures.install(admin, definition, bindings)

    {:ok, result} =
      WorkflowRuntime.command(clerk, %{
        "operation" => "create",
        "workflow_id" => version.workflow_id,
        "key" => Ecto.UUID.generate()
      })

    id = result["ticket_id"]

    {:ok, _} =
      Participants.command(
        admin,
        BuilderFixtures.participant_command(id, visitor.id, "create", 0)
      )

    {:ok, verified} =
      Participants.command(
        admin,
        BuilderFixtures.participant_command(id, visitor.id, "verify", 1)
      )

    {:ok, pending} =
      Participants.command(
        admin,
        BuilderFixtures.participant_command(id, unrelated.id, "create", 0)
      )

    reference = verified["relationship_id"]

    {:ok, view, _} =
      live(
        login(conn, admin),
        ~p"/o/horizonte/processos/#{version.workflow_id}/registros/#{id}"
      )

    assert has_element?(view, "#section-request-contact:not([disabled])")
    assert has_element?(view, "#section-request-contact option[value='#{reference}']")

    refute has_element?(
             view,
             "#section-request-contact option[value='#{pending["relationship_id"]}']"
           )

    view
    |> form("#directory-search-request-contact", directory: %{query: "does-not-exist"})
    |> render_change()

    refute has_element?(view, "#section-request-contact option[value='#{reference}']")

    view
    |> form("#directory-search-request-contact", directory: %{query: visitor.user.name})
    |> render_change()

    assert has_element?(view, "#section-request-contact option[value='#{reference}']")

    view
    |> form("#section-form-request",
      section: %{summary: "Verificado", contact: to_string(reference)}
    )
    |> render_submit()

    {:ok, data} = WorkflowRuntime.get(admin, id)
    assert hd(data.sections).values["contact"] == reference

    {:ok, _} =
      Participants.command(
        admin,
        BuilderFixtures.participant_command(id, visitor.id, "revoke", 2)
      )

    refute has_element?(view, "#section-request-contact option[value='#{reference}']")

    render_submit(view, "save", %{
      "key" => "request",
      "section" => %{"summary" => "Verificado", "contact" => to_string(reference)}
    })

    assert has_element?(view, "#flash-error", "referência deixou")
  end
end
