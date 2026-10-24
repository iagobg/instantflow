defmodule InstantflowWeb.Sprint11FieldSurfaceMatrixTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures
  alias Instantflow.{BuilderFixtures, Delivery, Participants, Repo, WorkflowRuntime}
  alias Instantflow.WorkflowCatalog.{Definition, Interchange, Templates, Version, Views}

  @cases [
    {"short_text", "Texto com acentuação", "Texto com acentuação", String.duplicate("x", 201)},
    {"long_text", "Primeira linha\nSegunda linha", "Primeira linha\nSegunda linha",
     String.duplicate("x", 10_001)},
    {"integer", "-42", -42, "9007199254740992"},
    {"money", "1250", 1250, "-1"},
    {"date", "2026-10-23", "2026-10-23", "2026-02-30"},
    {"datetime", "2026-10-23T14:30:00-03:00", "2026-10-23T14:30:00-03:00", "2026-10-23T14:30:00"},
    {"boolean", "false", false, "FORGED"},
    {"single_choice", "B", "B", "FORGED"},
    {"multiple_choice", ["", "A", "B"], ["A", "B"], ["", "FORGED"]}
  ]

  for surface <- [:staff, :participant], {type, submitted, expected, invalid} <- @cases do
    @surface surface
    @field_type type
    @submitted submitted
    @expected expected
    @invalid invalid
    test "#{surface} #{@field_type} roundtrips authoring, empty/typed/invalid/cleared form values, view and message" do
      f = setup_record(@surface, @field_type)
      actor = if @surface == :staff, do: f.clerk, else: f.visitor
      path = record_path(f, @surface)
      {:ok, view, _} = live(login(build_conn(), actor), path)

      input =
        if @surface == :staff,
          do: "section-#{f.section}-value",
          else: "participant-input-#{f.ref}"

      selector = "[id='#{input}']"
      assert has_element?(view, selector)

      if @field_type in ~w(boolean single_choice) do
        assert has_element?(view, selector <> " option[value='']")
      end

      if @field_type == "multiple_choice" do
        name = if @surface == :staff, do: "section[value][]", else: "field[value][]"
        assert has_element?(view, "input[type=hidden][name='#{name}'][value='']")
      end

      cleared =
        cond do
          @field_type in ~w(short_text long_text) -> ""
          @field_type == "multiple_choice" -> []
          true -> nil
        end

      empty = if @field_type == "multiple_choice", do: [""], else: ""
      submit(view, f, @surface, empty)
      assert read_value(actor, f) == cleared
      submit(view, f, @surface, @submitted)
      assert read_value(actor, f) == @expected

      if @field_type == "boolean" do
        submit(view, f, @surface, "true")
        assert read_value(actor, f) == true
        submit(view, f, @surface, "false")
        assert read_value(actor, f) == false
      end

      [row] = Views.search(f.admin, f.version.workflow_id, "matrix").rows
      assert Enum.find(row.cells, &(&1.key == f.ref)).value == @expected

      {:ok, sender, _} = live(login(build_conn(), f.admin), record_path(f, :staff))

      sender
      |> form("#release-matrix_notice", release: %{recipient: f.visitor.id})
      |> render_submit()

      [message] = Delivery.Curated.inbox(f.visitor, f.version.workflow_id).rows
      assert message.content == []
      assert {:ok, %{status: "succeeded"}} = Delivery.process(f.admin.organization_id, message.id)
      [message] = Delivery.Curated.inbox(f.visitor, f.version.workflow_id).rows
      assert [%{"label" => "Valor revisado", "value" => @expected}] == message.content

      # A fresh mount proves the saved typed value survives form reconstruction.
      {:ok, reloaded, _} = live(login(build_conn(), actor), path)

      assert_control(reloaded, selector, @field_type, @expected)

      forge(reloaded, f, @surface, @invalid)
      assert has_element?(reloaded, "#flash-error")
      assert read_value(actor, f) == @expected

      if @field_type == "multiple_choice" do
        forge(reloaded, f, @surface, ["", "A", "A"])
        assert read_value(actor, f) == @expected
      end

      submit(reloaded, f, @surface, empty)
      assert read_value(actor, f) == cleared
      [cleared_row] = Views.search(f.admin, f.version.workflow_id, "matrix").rows
      assert Enum.find(cleared_row.cells, &(&1.key == f.ref)).value == cleared
      [snapshot] = Delivery.Curated.inbox(f.visitor, f.version.workflow_id).rows
      assert snapshot.content == message.content

      {:ok, inbox, _} =
        live(
          login(build_conn(), f.visitor),
          "/o/horizonte/processos/#{f.version.workflow_id}/comunicacoes"
        )

      displayed =
        if is_binary(@expected),
          do: hd(String.split(@expected, <<10>>)),
          else: Jason.encode!(@expected)

      assert has_element?(inbox, "#curated-inbox article dd", displayed)
    end
  end

  defp setup_record(surface, type) do
    admin = staff_fixture()
    clerk = staff_fixture("staff")

    visitor =
      BuilderFixtures.invite_external(admin, "matrix-#{Ecto.UUID.generate()}@example.test")

    section = if surface == :staff, do: "request", else: "customer_details"
    ref = section <> ".value"
    field = %{"key" => "value", "label" => "Valor original", "type" => type}

    field =
      if type in ~w(single_choice multiple_choice),
        do: Map.put(field, "options", ["A", "B"]),
        else: field

    field = if type == "money", do: Map.put(field, "currency", "BRL"), else: field

    definition =
      BuilderFixtures.participant_page_definition()
      |> Map.put("template_key", "matrix_#{surface}_#{type}")
      |> Map.update!("capabilities", &(&1 ++ ["communications"]))
      |> Map.update!("sections", fn sections ->
        Enum.map(sections, fn s ->
          if s["key"] == section, do: Map.update!(s, "fields", &(&1 ++ [field])), else: s
        end)
      end)
      |> put_in(
        ["interface", "pages", Elixir.Access.at(1), "participant", "fields"],
        if(surface == :participant, do: [ref], else: ["customer_details.description"])
      )
      |> Map.put("views", [
        %{"key" => "matrix", "label" => "Matriz", "type" => "table", "columns" => ["stage", ref]}
      ])
      |> Map.put("communications", [
        %{
          "key" => "matrix_notice",
          "label" => "Valor selecionado",
          "recipient_relationship" => "claimant",
          "fields" => [ref],
          "behavior" => "success",
          "release_actors" => [
            %{
              "role" => "reviewer",
              "scope" => "workflow_department",
              "department_binding" => "responsible"
            }
          ]
        }
      ])

    assert :ok = Definition.validate(definition)
    {:ok, draft} = Templates.import(admin, Interchange.encode(definition))
    {:ok, editor, _} = live(login(build_conn(), admin), "/o/horizonte/modelos/#{draft.id}")

    editor
    |> form("#authoring-picker", picker: %{collection: "fields", section: section})
    |> render_submit()

    editor |> element("#edit-fields-#{section}-value") |> render_click()
    params = %{key: "value", label: "Valor revisado", type: type}

    params =
      if type in ~w(single_choice multiple_choice),
        do: Map.put(params, :options, "A\nB"),
        else: params

    params = if type == "money", do: Map.put(params, :currency, "BRL"), else: params
    editor |> form("#template-item-form", item: params) |> render_submit()

    editor
    |> form("#template-mappings",
      mapping: %{
        roles: %{requester: ["staff"], reviewer: ["admin"], visitor: ["external"]},
        departments: %{responsible: admin.department_id},
        assignment: "responsible"
      }
    )
    |> render_submit()

    refute has_element?(editor, "#publish-template[disabled]")
    editor |> element("#publish-template") |> render_click()
    editor |> element("#confirm-publish-template") |> render_click()
    {:ok, published} = Templates.get(admin, draft.id)
    version = Repo.get!(Version, published.published_version_id)
    assert Definition.fields(version.definition)[ref] == Map.put(field, "label", "Valor revisado")
    {:ok, exported} = Templates.export(admin, :version, version.id)

    {:ok, imported} =
      Templates.import(admin, exported.json, %{"template_key" => "copy_#{surface}_#{type}"})

    assert Definition.fields(imported.definition)[ref] ==
             Definition.fields(version.definition)[ref]

    assert imported.bindings == %{"roles" => %{}, "departments" => %{}}

    {:ok, created} =
      WorkflowRuntime.command(clerk, %{
        "operation" => "create",
        "workflow_id" => version.workflow_id,
        "key" => Ecto.UUID.generate()
      })

    id = created["ticket_id"]

    for {op, revision} <- [{"create", 0}, {"verify", 1}] do
      {:ok, _} =
        Participants.command(
          admin,
          BuilderFixtures.participant_command(id, visitor.id, op, revision)
        )
    end

    {:ok, _} =
      Instantflow.WorkflowFixtures.transition(admin, id, "request_changes", "Correção sintética")

    %{
      admin: admin,
      clerk: clerk,
      visitor: visitor,
      version: version,
      id: id,
      section: section,
      ref: ref
    }
  end

  defp record_path(f, :staff),
    do: "/o/horizonte/processos/#{f.version.workflow_id}/registros/#{f.id}"

  defp record_path(f, :participant),
    do: "/o/horizonte/processos/#{f.version.workflow_id}/participacao/my_packet/registros/#{f.id}"

  defp submit(view, f, surface, value) do
    case surface do
      :staff ->
        view
        |> form("#section-form-#{f.section}", section: %{"value" => value})
        |> render_submit()

      :participant ->
        view
        |> form("[id='participant-field-#{f.ref}']", field: %{"value" => value})
        |> render_submit()
    end
  end

  # Extra submit data represents an attacker bypassing rendered select/number constraints.
  defp forge(view, f, :staff, value),
    do:
      view
      |> form("#section-form-#{f.section}")
      |> render_submit(%{"section" => %{"value" => value}})

  defp forge(view, f, :participant, value),
    do:
      view
      |> form("[id='participant-field-#{f.ref}']")
      |> render_submit(%{"field" => %{"value" => value}})

  defp assert_control(view, selector, "multiple_choice", values) do
    for option <- values,
        do: assert(has_element?(view, selector <> " option[value='#{option}'][selected]"))
  end

  defp assert_control(view, selector, type, value) when type in ~w(boolean single_choice),
    do: assert(has_element?(view, selector <> " option[value='#{value}'][selected]"))

  defp assert_control(view, selector, "long_text", value),
    do: assert(has_element?(view, selector, hd(String.split(value, <<10>>))))

  defp assert_control(view, selector, _, value),
    do: assert(has_element?(view, selector <> "[value='#{value}']"))

  defp read_value(actor, f) do
    {:ok, data} = WorkflowRuntime.get(actor, f.id)
    Enum.find(data.sections, &(&1.key == f.section)).values["value"]
  end
end
