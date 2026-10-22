defmodule InstantflowWeb.Sprint10ReviewRegressionsTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures

  alias Instantflow.{
    Access,
    BuilderFixtures,
    Identity,
    Participants,
    PrivateDocuments,
    WorkflowRuntime
  }

  alias Instantflow.WorkflowCatalog.Templates

  test "unselected documents deny direct HTTP and context downloads while staff retain access" do
    definition =
      put_in(
        BuilderFixtures.participant_page_definition(),
        ["interface", "pages", Elixir.Access.at(1), "participant", "documents"],
        []
      )

    f = setup_record(definition)
    doc = ready_document(f, "evidence")

    assert {:ok, %{documents: []}} =
             Instantflow.WorkflowRuntime.ParticipantPages.get(
               f.visitor,
               f.version.workflow_id,
               "my_packet",
               f.id
             )

    assert {:error, :forbidden} =
             Instantflow.WorkflowRuntime.ParticipantPages.upload(
               f.visitor,
               f.version.workflow_id,
               "my_packet",
               f.id,
               "customer_details.evidence",
               "proof.pdf",
               Instantflow.EnrollmentFixtures.pdf(),
               Ecto.UUID.generate()
             )

    assert {:error, :not_found} = PrivateDocuments.download(f.visitor, doc.object_key)
    assert download(f.visitor, doc).status == 404
    assert download(f.admin, doc).status == 200
    parent = staff_fixture("parent")
    {:ok, _} = Access.grant(f.admin, parent.id, parent.department_id, "teacher")
    assert download(Identity.scope(parent.user_id, parent.organization_id), doc).status == 200
  end

  test "selected direct downloads use pinned pages and exact fields, then reauthorize revoked relationships" do
    definition =
      update_in(
        BuilderFixtures.participant_page_definition(),
        ["sections", Elixir.Access.at(1), "fields"],
        fn fields ->
          selected = Enum.find(fields, &(&1["key"] == "evidence"))
          fields ++ [Map.put(selected, "key", "unselected")]
        end
      )

    f = setup_record(definition)
    selected = ready_document(f, "evidence")
    unselected = ready_document(f, "unselected")
    assert download(f.visitor, selected).status == 200
    assert download(f.visitor, unselected).status == 404
    {:ok, draft} = Templates.clone(f.admin, f.version.id)

    revised =
      put_in(draft.definition, ["interface", "pages"], [
        hd(draft.definition["interface"]["pages"])
      ])

    {:ok, saved} = Templates.save(f.admin, draft.id, draft.revision, revised, f.bindings)
    {:ok, _} = Templates.publish(f.admin, saved.id, saved.revision)
    assert download(f.visitor, selected).status == 200
    assert download(f.visitor, unselected).status == 404

    {:ok, _} =
      Participants.command(
        f.admin,
        BuilderFixtures.participant_command(f.id, f.visitor.id, "revoke", 2)
      )

    assert download(f.visitor, selected).status == 404
  end

  test "loss of page admission denies a selected URL even while underlying section read authority remains" do
    definition =
      BuilderFixtures.participant_page_definition()
      |> Map.update!(
        "role_requirements",
        &(&1 ++ [%{"key" => "page_reader", "label" => "Leitor da página"}])
      )
      |> put_in(["interface", "pages", Elixir.Access.at(1), "participant", "visibility_roles"], [
        "page_reader"
      ])

    f = setup_record(definition)
    doc = ready_document(f, "evidence")
    {:ok, {_, grant}} = Access.grant(f.admin, f.visitor.id, f.visitor.department_id, "head")
    assert download(f.visitor, doc).status == 200
    {:ok, _} = Access.revoke(f.admin, grant.id)
    assert {:ok, data} = WorkflowRuntime.get(f.visitor, f.id)
    assert Enum.any?(data.sections, &(&1.key == "customer_details"))
    assert {:error, :not_found} = PrivateDocuments.download(f.visitor, doc.object_key)
    assert download(f.visitor, doc).status == 404
  end

  for surface <- [:participant, :staff] do
    @surface surface
    test "#{surface} multiple choice selects and clears browser values but rejects forged options" do
      assert_multiple_choice(@surface)
    end
  end

  defp assert_multiple_choice(surface) do
    index = if surface == :participant, do: 1, else: 0
    section = if surface == :participant, do: "customer_details", else: "request"

    definition =
      update_in(
        BuilderFixtures.participant_page_definition(),
        ["sections", Elixir.Access.at(index), "fields"],
        fn fields ->
          fields ++
            [
              %{
                "key" => "choices",
                "label" => "Escolhas",
                "type" => "multiple_choice",
                "options" => ["A", "B"]
              }
            ]
        end
      )

    definition =
      if surface == :participant,
        do:
          put_in(
            definition,
            ["interface", "pages", Elixir.Access.at(1), "participant", "fields"],
            ["customer_details.choices"]
          ),
        else: definition

    f = setup_record(definition)
    actor = if surface == :participant, do: f.visitor, else: f.clerk

    path =
      if surface == :participant,
        do:
          "/o/horizonte/processos/#{f.version.workflow_id}/participacao/my_packet/registros/#{f.id}",
        else: "/o/horizonte/processos/#{f.version.workflow_id}/registros/#{f.id}"

    {:ok, view, _} = live(login(build_conn(), actor), path)
    name = if surface == :participant, do: "field[value][]", else: "section[choices][]"
    assert has_element?(view, "input[type=hidden][name='#{name}'][value='']")

    for {submitted, expected} <- [{["", "A"], ["A"]}, {[""], []}, {["", "FORGED"], []}] do
      if surface == :participant do
        view
        |> form("[id='participant-field-customer_details.choices']")
        |> render_submit(%{"field" => %{"value" => submitted}})
      else
        view
        |> form("#section-form-request")
        |> render_submit(%{"section" => %{"choices" => submitted}})
      end

      {:ok, data} = WorkflowRuntime.get(actor, f.id)
      assert Enum.find(data.sections, &(&1.key == section)).values["choices"] == expected
    end

    assert has_element?(view, "#flash-error")
  end

  defp setup_record(definition) do
    admin = staff_fixture()
    clerk = staff_fixture("staff")

    visitor =
      BuilderFixtures.invite_external(admin, "review-#{Ecto.UUID.generate()}@example.test")

    roles = %{
      "requester" => ["staff"],
      "reviewer" => ["admin", "teacher"],
      "visitor" => ["external"]
    }

    roles =
      if Enum.any?(definition["role_requirements"], &(&1["key"] == "page_reader")),
        do: Map.put(roles, "page_reader", ["head"]),
        else: roles

    bindings = %{"roles" => roles, "departments" => %{"responsible" => admin.department_id}}
    version = BuilderFixtures.install(admin, definition, bindings)

    {:ok, created} =
      WorkflowRuntime.command(clerk, %{
        "operation" => "create",
        "workflow_id" => version.workflow_id,
        "key" => Ecto.UUID.generate()
      })

    id = created["ticket_id"]

    for {op, revision} <- [{"create", 0}, {"verify", 1}],
        do:
          {:ok, _} =
            Participants.command(
              admin,
              BuilderFixtures.participant_command(id, visitor.id, op, revision)
            )

    {:ok, _} =
      Instantflow.WorkflowFixtures.transition(admin, id, "request_changes", "Correção sintética")

    %{admin: admin, clerk: clerk, visitor: visitor, version: version, id: id, bindings: bindings}
  end

  defp ready_document(f, field) do
    {:ok, doc} =
      PrivateDocuments.upload(
        f.visitor,
        f.id,
        "customer_details",
        field,
        "proof.pdf",
        Instantflow.EnrollmentFixtures.pdf()
      )

    {:ok, _} = PrivateDocuments.review(f.admin, doc.object_key, true)
    doc
  end

  defp download(actor, doc),
    do: get(login(build_conn(), actor), "/o/horizonte/documentos/#{doc.object_key}")
end
