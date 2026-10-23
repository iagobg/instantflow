defmodule Instantflow.WorkflowRuntime.ProjectionsTest do
  use Instantflow.DataCase, async: true
  import Instantflow.IdentityFixtures
  alias Instantflow.{BuilderFixtures, Participants, WorkflowRuntime}
  alias Instantflow.WorkflowCatalog.{Views, Templates}
  alias Instantflow.WorkflowRuntime.{Policy, Projections, Section, Ticket}

  test "SQL authorization precedes pagination and metadata; mixed versions use batched projections" do
    f = fixture()
    first = create(f.clerk, f.version)
    link(f.admin, f.visitor, first)

    baseline =
      measured(fn -> Views.search(f.visitor, f.version.workflow_id, "participant_work") end)

    assert [%{id: ^first}] = baseline.result.rows

    accessible = for _ <- 1..27, do: create(f.clerk, f.version)
    Enum.each(accessible, &link(f.admin, f.visitor, &1))
    hidden = for _ <- 1..45, do: create(f.clerk, f.version)
    # The newest records are inaccessible. Paging first would return no rows.
    Enum.each(hidden, &link(f.admin, f.other, &1))

    {:ok, draft} = Templates.clone(f.admin, f.version.id)
    changed = put_in(f.definition, ["stages", Access.at(0), "label"], "Nova etapa")
    {:ok, saved} = Templates.save(f.admin, draft.id, draft.revision, changed, f.bindings)
    {:ok, second} = Templates.publish(f.admin, saved.id, saved.revision)
    latest = create(f.clerk, second)
    link(f.admin, f.visitor, latest)

    many = measured(fn -> Views.search(f.visitor, f.version.workflow_id, "participant_work") end)
    assert many.result.total == 29
    assert length(many.result.rows) == 25
    assert many.result.page == 1 and many.result.pages == 2

    assert Enum.map(many.result.rows, & &1.id) ==
             Enum.take(Enum.sort([latest, first | accessible], :desc), 25)

    assert hd(many.result.rows).stage_label == "Nova etapa"
    assert Enum.at(many.result.rows, 1).stage_label != "Nova etapa"
    assert length(many.queries) == length(baseline.queries)

    section_queries =
      Enum.filter(many.queries, &String.contains?(&1.query, ~s(FROM "ticket_sections")))

    assert length(section_queries) == 1
    assert length(hd(section_queries).result.rows) == 25
    ticket_queries = Enum.filter(many.queries, &String.contains?(&1.query, ~s(FROM "tickets")))
    assert Enum.any?(ticket_queries, &String.contains?(&1.query, "LIMIT"))

    page2 =
      Projections.search(f.visitor, %{"workflow_id" => f.version.workflow_id, "page" => "2"})

    assert length(page2.tickets) == 4
    assert page2.total == 29 and page2.filtered == 29
    refute Map.has_key?(page2, :versions)
    assert Enum.all?(page2.tickets, &(&1.workflow_version.bindings == %{}))

    assert Enum.sort(Enum.map(page2.tickets, & &1.id)) ==
             Enum.take(Enum.sort([first | accessible]), 4)

    filtered =
      Projections.search(f.visitor, %{"workflow_id" => f.version.workflow_id, "stage" => "closed"})

    assert filtered.total == 29 and filtered.filtered == 0 and filtered.tickets == []
    assert Views.search(f.visitor, f.version.workflow_id, "missing").total == 0
    assert Views.search(f.visitor, f.version.workflow_id, "staff_only").total == 0
    assert Enum.all?(Views.options(f.visitor), &String.ends_with?(&1.id, ":participant_work"))
    assert Projections.search(f.unrelated).total == 0
    assert Views.options(f.unrelated) == []
  end

  test "idle publications and unrelated empty processes do not expand record policy loading" do
    f = fixture()
    id = create(f.clerk, f.version)
    link(f.admin, f.visitor, id)

    before =
      measured(fn -> Views.search(f.visitor, f.version.workflow_id, "participant_work") end)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    changed =
      put_in(
        f.definition,
        ["stages", Access.at(0), "label"],
        "Unused stage until a record pins it"
      )

    rows =
      for number <- 2..101 do
        %{
          organization_id: f.admin.organization_id,
          workflow_id: f.version.workflow_id,
          number: number,
          definition: changed,
          bindings: f.bindings,
          published_by_id: f.admin.user_id,
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(Instantflow.WorkflowCatalog.Version, rows)

    for number <- 1..30 do
      workflow =
        Repo.insert!(%Instantflow.WorkflowCatalog.Workflow{
          organization_id: f.admin.organization_id,
          key: "idle_process_#{number}",
          name: "Unused process"
        })

      Repo.insert!(%Instantflow.WorkflowCatalog.Version{
        organization_id: f.admin.organization_id,
        workflow_id: workflow.id,
        number: 1,
        definition: Map.put(f.definition, "template_key", workflow.key),
        bindings: f.bindings,
        published_by_id: f.admin.user_id
      })
    end

    after_growth =
      measured(fn -> Views.search(f.visitor, f.version.workflow_id, "participant_work") end)

    assert after_growth.result == before.result
    assert catalog_rows(after_growth) == catalog_rows(before)
    assert catalog_rows(after_growth) == 1
    assert max_sql_bytes(after_growth) == max_sql_bytes(before)
    options = measured(fn -> Views.options(f.visitor) end)
    assert catalog_rows(options) == 1
    assert Enum.all?(options.result, &(&1.workflow_id == f.version.workflow_id))

    latest = create(f.clerk, f.version)
    link(f.admin, f.visitor, latest)
    mixed = measured(fn -> Views.search(f.visitor, f.version.workflow_id, "participant_work") end)
    assert mixed.result.total == 2
    assert catalog_rows(mixed) == 1
    # One shared body still expands into both distinct immutable stage pins.
    assert Enum.map(mixed.result.rows, & &1.id) == [latest, id]
    assert hd(mixed.result.rows).stage_label == "Unused stage until a record pins it"
    assert List.last(mixed.result.rows).stage_label != hd(mixed.result.rows).stage_label

    {:ok, _} =
      Participants.command(
        f.admin,
        BuilderFixtures.participant_command(latest, f.visitor.id, "revoke", 2)
      )

    assert Views.search(f.visitor, f.version.workflow_id, "participant_work").total == 1
  end

  defp catalog_rows(measurement) do
    measurement.queries
    |> Enum.filter(&(&1[:source] == "workflow_versions"))
    |> Enum.map(&length(&1.result.rows))
    |> Enum.sum()
  end

  defp max_sql_bytes(measurement),
    do: measurement.queries |> Enum.map(&byte_size(&1.query)) |> Enum.max()

  test "query policy matches command policy and current revocation for participant and staff grants" do
    f = fixture()
    id = create(f.clerk, f.version)
    link(f.admin, f.visitor, id)
    parent = staff_fixture("parent")

    {:ok, {_, grant}} =
      Instantflow.Access.grant(f.admin, parent.id, parent.department_id, "teacher")

    for scope <- [f.admin, f.clerk, f.visitor, f.other, f.unrelated, parent] do
      expected =
        Instantflow.Tenant.read(scope, fn fresh ->
          ticket = Repo.get!(Ticket, id)
          Policy.discover?(fresh, ticket, f.version)
        end)

      result = Projections.search(scope, %{"workflow_id" => f.version.workflow_id})
      assert result.total == 1 == expected
    end

    assert Projections.search(parent).total == 1
    {:ok, _} = Instantflow.Access.revoke(f.admin, grant.id)
    assert Projections.search(parent).total == 0

    assert {:ok, _} =
             Participants.command(
               f.admin,
               BuilderFixtures.participant_command(id, f.visitor.id, "revoke", 2)
             )

    assert Projections.search(f.visitor).total == 0
    assert Views.options(f.visitor) == []
    assert Views.search(f.visitor, f.version.workflow_id, "participant_work").rows == []
  end

  test "named confidential assignments and grant removal match detail authorization" do
    f = Instantflow.IncidentFixtures.incident_fixture()
    id = Instantflow.IncidentFixtures.report(f)
    assert Projections.search(f.counselor).total == 0
    assert {:ok, _} = Instantflow.IncidentFixtures.assign(f.dean, id, f.counselor.id, "Sintético")
    assert Projections.search(f.counselor).total == 1
    assert Projections.search(f.other_counselor).total == 0
    assert Projections.search(f.admin).total == 0
    assert {:ok, _} = Instantflow.IncidentFixtures.assign(f.dean, id, nil, "Revogar")
    assert Projections.search(f.counselor).total == 0
  end

  test "hidden section values never reach projection results or influence text search" do
    f = fixture()
    id = create(f.clerk, f.version)
    link(f.admin, f.visitor, id)

    Repo.update_all(from(s in Section, where: s.ticket_id == ^id and s.key == "request"),
      set: [values: %{"summary" => "INTERNAL-SECRET"}]
    )

    measured =
      measured(fn -> Views.search(f.visitor, f.version.workflow_id, "participant_work") end)

    refute inspect(measured.result) =~ "INTERNAL-SECRET"

    sections =
      Enum.filter(measured.queries, &String.contains?(&1.query, ~s(FROM "ticket_sections")))

    refute inspect(Enum.map(sections, & &1.result)) =~ "INTERNAL-SECRET"
    assert Projections.search(f.visitor, %{"query" => "INTERNAL-SECRET"}).filtered == 0
    assert Projections.search(f.visitor, %{"page" => %{}, "query" => []}).total == 1
    assert Projections.search(f.visitor, %{"workflow_id" => "invalid"}).total == 0
  end

  test "a verified read-only subject reference does not authorize query metadata" do
    f = fixture()

    definition =
      f.definition
      |> Map.put("template_key", "subject_projection")
      |> put_in(["participants", Access.at(0), "kind"], "subject")
      |> put_in(["sections", Access.at(1), "access"], [
        %{
          "role" => "reviewer",
          "scope" => "workflow_department",
          "department_binding" => "responsible",
          "read" => true,
          "edit_stages" => []
        }
      ])

    version = BuilderFixtures.install(f.admin, definition, f.bindings)
    id = create(f.clerk, version)
    link(f.admin, f.visitor, id)
    assert {:error, :not_found} = WorkflowRuntime.get(f.visitor, id)
    assert Projections.search(f.visitor).tickets == []
    assert Projections.search(f.visitor).counts == %{}
    assert Projections.search(f.visitor).stage_labels == %{}
    assert Views.options(f.visitor) == []
    assert Views.search(f.visitor, version.workflow_id, "participant_work").total == 0
    assert Projections.search(f.admin).total == 1
  end

  defp fixture do
    admin = staff_fixture()
    clerk = staff_fixture("staff")
    visitor = BuilderFixtures.invite_external(admin, "query-#{Ecto.UUID.generate()}@example.test")
    other = BuilderFixtures.invite_external(admin, "query-#{Ecto.UUID.generate()}@example.test")

    unrelated =
      BuilderFixtures.invite_external(admin, "query-#{Ecto.UUID.generate()}@example.test")

    definition =
      BuilderFixtures.participant_definition("projected_intake")
      |> Map.put("views", [
        %{
          "key" => "participant_work",
          "label" => "Meu trabalho",
          "type" => "table",
          "columns" => ["stage", "customer_details.description"]
        },
        %{
          "key" => "staff_only",
          "label" => "Interno",
          "type" => "table",
          "columns" => ["request.summary"]
        }
      ])

    bindings = %{
      "roles" => %{
        "requester" => ["staff"],
        "reviewer" => ["admin", "teacher"],
        "visitor" => ["external"]
      },
      "departments" => %{"responsible" => admin.department_id}
    }

    version = BuilderFixtures.install(admin, definition, bindings)

    %{
      admin: admin,
      clerk: clerk,
      visitor: visitor,
      other: other,
      unrelated: unrelated,
      version: version,
      definition: definition,
      bindings: bindings
    }
  end

  defp create(actor, version) do
    {:ok, result} =
      WorkflowRuntime.command(actor, %{
        "operation" => "create",
        "workflow_id" => version.workflow_id,
        "key" => Ecto.UUID.generate()
      })

    result["ticket_id"]
  end

  defp link(admin, member, id) do
    for {op, revision} <- [{"create", 0}, {"verify", 1}] do
      {:ok, _} =
        Participants.command(
          admin,
          BuilderFixtures.participant_command(id, member.id, op, revision)
        )
    end
  end

  defp measured(fun) do
    id = Ecto.UUID.generate()
    :telemetry.attach(id, [:instantflow, :repo, :query], &__MODULE__.capture/4, self())

    try do
      result = fun.()
      %{result: result, queries: drain([])}
    after
      :telemetry.detach(id)
    end
  end

  @doc false
  def capture(_, _, metadata, pid) do
    if self() == pid,
      do: send(pid, {:projection_query, Map.take(metadata, [:query, :result, :source])})
  end

  defp drain(acc) do
    receive do
      {:projection_query, %{result: {:ok, result}} = metadata} ->
        drain([%{metadata | result: result} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
