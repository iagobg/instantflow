defmodule InstantflowWeb.DiscoveryPaginationLiveTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures

  alias Instantflow.{
    Access,
    BuilderFixtures,
    Delivery,
    FinanceFixtures,
    Participants,
    WorkflowRuntime
  }

  alias Instantflow.WorkflowCatalog.{Templates, Views, Workspaces}
  alias Instantflow.WorkflowRuntime.Projections

  test "process discovery reaches later pages and creates from a directly selected later workspace" do
    admin = staff_fixture()
    actor = staff_fixture("staff")
    bindings = bindings(admin)

    versions =
      for n <- 1..30,
          do:
            BuilderFixtures.install(
              admin,
              Templates.starter("process_#{n}", "Processo #{n}"),
              bindings
            )

    target = List.last(versions)
    {:ok, list, _} = live(login(build_conn(), actor), "/o/horizonte/processos")
    assert has_element?(list, "#process-discovery-count", "30 processo(s)")
    refute has_element?(list, "#open-process-#{target.workflow_id}")
    list |> element("#process-discovery-next") |> render_click()
    assert has_element?(list, "#open-process-#{target.workflow_id}")

    list
    |> form("#process-discovery-filters", discovery: %{query: "Processo 30"})
    |> render_submit()

    assert has_element?(list, "#process-discovery-count", "1 processo(s)")
    assert has_element?(list, "#open-process-#{target.workflow_id}")

    {:ok, process, _} =
      live(login(build_conn(), actor), "/o/horizonte/processos/#{target.workflow_id}")

    assert has_element?(process, "#create-process-record")
    process |> element("#create-process-record") |> render_click()
    [ticket] = WorkflowRuntime.search(actor, %{"workflow_id" => target.workflow_id}).tickets

    assert_redirect(
      process,
      "/o/horizonte/processos/#{target.workflow_id}/registros/#{ticket.id}"
    )
  end

  test "publication and current grant invalidation refresh pure-layout navigation" do
    admin = staff_fixture()
    actor = staff_fixture("staff")
    {:ok, home, _} = live(login(build_conn(), actor), "/o/horizonte")

    version =
      BuilderFixtures.install(
        admin,
        Templates.starter("published_live", "Publicado agora"),
        bindings(admin)
      )

    assert has_element?(home, "#process-link-#{version.workflow_id}")
    limited = put_in(bindings(admin), ["roles", "requester"], ["operations"])

    gated =
      BuilderFixtures.install(
        admin,
        Templates.starter("grant_live", "Acesso por concessão"),
        limited
      )

    refute has_element?(home, "#process-link-#{gated.workflow_id}")
    {:ok, {_, grant}} = Access.grant(admin, actor.id, actor.department_id, "operations")
    assert has_element?(home, "#process-link-#{gated.workflow_id}")
    {:ok, _} = Access.revoke(admin, grant.id)
    refute has_element?(home, "#process-link-#{gated.workflow_id}")
    assert Workspaces.get(actor, gated.workflow_id) == nil
  end

  test "later participant/inbox/view choices remain reachable and relationship revocation updates counts" do
    admin = staff_fixture()
    clerk = staff_fixture("staff")

    visitor =
      BuilderFixtures.invite_external(admin, "paged-entry-#{Ecto.UUID.generate()}@example.test")

    bindings =
      Map.put(bindings(admin), "roles", %{
        "requester" => ["staff"],
        "reviewer" => ["admin"],
        "visitor" => ["external"]
      })

    records =
      for n <- 1..30 do
        definition =
          BuilderFixtures.participant_page_definition()
          |> Map.put("template_key", "entry_#{n}")
          |> Map.put("name", "Entrada #{n}")
          |> Map.update!("capabilities", &(&1 ++ ["communications"]))
          |> Map.put("communications", [
            %{
              "key" => "notice",
              "label" => "Resumo",
              "recipient_relationship" => "claimant",
              "fields" => ["customer_details.description"],
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

        version = BuilderFixtures.install(admin, definition, bindings)

        {:ok, created} =
          WorkflowRuntime.command(clerk, %{
            "operation" => "create",
            "workflow_id" => version.workflow_id,
            "key" => Ecto.UUID.generate()
          })

        id = created["ticket_id"]

        for {op, rev} <- [{"create", 0}, {"verify", 1}] do
          {:ok, _} =
            Participants.command(
              admin,
              BuilderFixtures.participant_command(id, visitor.id, op, rev)
            )
        end

        {:ok, _} =
          Instantflow.WorkflowFixtures.transition(
            admin,
            id,
            "request_changes",
            "Correção sintética"
          )

        {:ok, _} =
          FinanceFixtures.save(visitor, id, "customer_details", %{"description" => "Resumo #{n}"})

        {:ok, data} = WorkflowRuntime.get(admin, id)

        {:ok, _} =
          Delivery.Curated.release(
            admin,
            id,
            "notice",
            visitor.id,
            data.ticket.revision,
            Ecto.UUID.generate()
          )

        {version, id}
      end

    {last, last_id} = List.last(records)
    assert Projections.participant_discovery(visitor).total == 30
    assert length(Projections.participant_discovery(visitor).rows) == 25
    assert length(Projections.participant_discovery(visitor, %{"page" => "2"}).rows) == 5
    assert Delivery.Curated.discovery(visitor).total == 30
    assert length(Delivery.Curated.discovery(visitor, %{"page" => "2"}).rows) == 5
    assert Views.discovery(clerk).total == 30
    assert length(Views.discovery(clerk, %{"page" => "2"}).rows) == 5
    {:ok, entry, _} = live(login(build_conn(), visitor), "/o/horizonte/processos")
    refute has_element?(entry, "#participant-entry-#{last.workflow_id}-my_packet")
    entry |> element("#participant-discovery-next") |> render_click()
    entry |> element("#inbox-discovery-next") |> render_click()
    assert has_element?(entry, "#participant-entry-#{last.workflow_id}-my_packet")
    assert has_element?(entry, "#inbox-entry-#{last.workflow_id}")
    assert has_element?(entry, "#participant-entry-pages h2", "Entrada 30")
    {:ok, requests, _} = live(login(build_conn(), clerk), "/o/horizonte/solicitacoes")
    requests |> element("#global-view-browser-next") |> render_click()
    choice = hd(Views.discovery(clerk, %{"workflow_id" => last.workflow_id}).rows)
    requests |> form("#configured-view-form", view: %{key: choice.id}) |> render_submit()
    assert has_element?(requests, "#configured-view-count", "1 resultado(s)")

    {:ok, _} =
      Participants.command(
        admin,
        BuilderFixtures.participant_command(last_id, visitor.id, "revoke", 2)
      )

    assert has_element?(entry, "#participant-discovery-count", "29 página(s)")
    assert has_element?(entry, "#inbox-discovery-count", "29 caixa(s)")
    refute has_element?(entry, "#participant-entry-#{last.workflow_id}-my_packet")
    refute has_element?(entry, "#inbox-entry-#{last.workflow_id}")
  end

  defp bindings(admin),
    do: %{
      "roles" => %{"requester" => ["staff"], "reviewer" => ["admin"]},
      "departments" => %{"responsible" => admin.department_id}
    }
end
