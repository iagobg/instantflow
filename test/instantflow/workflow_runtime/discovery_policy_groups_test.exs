defmodule Instantflow.WorkflowRuntime.DiscoveryPolicyGroupsTest do
  use Instantflow.DataCase, async: true
  import Instantflow.IdentityFixtures

  alias Instantflow.{
    Access,
    BuilderFixtures,
    Delivery,
    FinanceFixtures,
    Participants,
    WorkflowFixtures,
    WorkflowRuntime
  }

  alias Instantflow.WorkflowCatalog.Templates
  alias Instantflow.WorkflowRuntime.Projections

  test "equivalent independent processes share bounded predicates while changed bindings, old pins and live revocation stay separate" do
    admin = staff_fixture()

    external =
      BuilderFixtures.invite_external(admin, "grouped-#{Ecto.UUID.generate()}@example.test")

    d = definition("grouped_alpha")

    bindings = %{
      "roles" => %{"requester" => ["admin"], "reviewer" => ["admin"], "visitor" => ["external"]},
      "departments" => %{"responsible" => admin.department_id}
    }

    first = BuilderFixtures.install(admin, d, bindings)
    first_ticket = create(admin, first)
    release(admin, external, first_ticket, "First snapshot")
    baseline = measured(fn -> Projections.participant_discovery(external) end)
    inbox_baseline = measured(fn -> Delivery.Curated.discovery(external) end)

    second =
      BuilderFixtures.install(
        admin,
        Map.put(d, "template_key", "grouped_bravo") |> Map.put("name", "Independent second"),
        bindings
      )

    second_ticket = create(admin, second)
    release(admin, external, second_ticket, "Second snapshot")
    both = measured(fn -> Projections.participant_discovery(external) end)
    inbox_both = measured(fn -> Delivery.Curated.discovery(external) end)
    assert both.result.total == 2 and inbox_both.result.total == 2
    assert both.sql_bytes <= baseline.sql_bytes + 128
    assert inbox_both.sql_bytes <= inbox_baseline.sql_bytes + 128

    assert Enum.sort(Enum.map(both.result.rows, & &1.workflow_id)) ==
             Enum.sort([first.workflow_id, second.workflow_id])

    {:ok, draft} = Templates.clone(admin, first.id)
    changed_bindings = put_in(bindings, ["roles", "visitor"], ["teacher"])

    {:ok, saved} =
      Templates.save(admin, draft.id, draft.revision, draft.definition, changed_bindings)

    {:ok, new_pin} = Templates.publish(admin, saved.id, saved.revision)
    {:ok, {_, grant}} = Access.grant(admin, external.id, external.department_id, "teacher")
    third_ticket = create(admin, new_pin)
    release(admin, external, third_ticket, "New binding snapshot")
    assert Projections.participant_search(external, first.workflow_id, "my_packet").total == 2
    assert Delivery.Curated.inbox(external, first.workflow_id).total == 2
    {:ok, _} = Access.revoke(admin, grant.id)
    assert Projections.participant_search(external, first.workflow_id, "my_packet").total == 1
    assert Delivery.Curated.inbox(external, first.workflow_id).total == 1
    assert {:error, :not_found} = WorkflowRuntime.get(external, third_ticket)
    assert {:ok, _} = WorkflowRuntime.get(external, first_ticket)

    assert {:ok, _} =
             Participants.command(
               admin,
               BuilderFixtures.participant_command(first_ticket, external.id, "revoke", 2)
             )

    assert Projections.participant_discovery(external).total == 1
    assert Delivery.Curated.discovery(external).total == 1
    assert Projections.participant_search(external, second.workflow_id, "my_packet").total == 1
  end

  defp definition(key) do
    BuilderFixtures.participant_page_definition()
    |> Map.put("template_key", key)
    |> Map.update!("capabilities", &(&1 ++ ["communications"]))
    |> Map.put("communications", [
      %{
        "key" => "grouped_notice",
        "label" => "Result",
        "recipient_relationship" => "claimant",
        "fields" => ["customer_details.description"],
        "release_actors" => [
          %{
            "role" => "reviewer",
            "scope" => "workflow_department",
            "department_binding" => "responsible"
          }
        ],
        "behavior" => "success"
      }
    ])
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

  defp release(admin, external, ticket, text) do
    for {op, revision} <- [{"create", 0}, {"verify", 1}],
        do:
          assert(
            {:ok, _} =
              Participants.command(
                admin,
                BuilderFixtures.participant_command(ticket, external.id, op, revision)
              )
          )

    {:ok, _} =
      WorkflowFixtures.transition(admin, ticket, "request_changes", "Synthetic correction")

    {:ok, _} =
      FinanceFixtures.save(external, ticket, "customer_details", %{"description" => text})

    {:ok, data} = WorkflowRuntime.get(admin, ticket)

    assert {:ok, _} =
             Delivery.Curated.release(
               admin,
               ticket,
               "grouped_notice",
               external.id,
               data.ticket.revision,
               Ecto.UUID.generate()
             )
  end

  defp measured(fun) do
    key = "discovery-policy-group-#{Ecto.UUID.generate()}"
    Process.put(:grouped_sql_bytes, 0)

    :telemetry.attach(
      key,
      [:instantflow, :repo, :query],
      fn _, _, metadata, _ ->
        if bytes = Process.get(:grouped_sql_bytes),
          do: Process.put(:grouped_sql_bytes, max(bytes, byte_size(metadata.query)))
      end,
      nil
    )

    try do
      %{result: fun.(), sql_bytes: Process.get(:grouped_sql_bytes)}
    after
      :telemetry.detach(key)
      Process.delete(:grouped_sql_bytes)
    end
  end
end
