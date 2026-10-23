defmodule Instantflow.WorkflowCatalog.CapabilityMatrixTest do
  use Instantflow.DataCase, async: true
  import Instantflow.IdentityFixtures
  alias Instantflow.{BuilderFixtures, Operations, WorkflowRuntime}

  alias Instantflow.WorkflowCatalog.{
    Capabilities,
    Definition,
    Interchange,
    OperationalContract,
    Templates
  }

  test "every additive capability subset enforces declared dependencies with portable paths" do
    cases = subsets()
    assert length(cases) == 32
    assert Enum.count(cases, &supported?/1) == 24

    for capabilities <- cases do
      d = definition(capabilities)
      assert :ok = Definition.validate_draft(d)
      {:ok, decoded} = d |> Interchange.encode() |> Interchange.decode()

      if supported?(capabilities) do
        assert :ok = Definition.validate(d)
        assert :ok = Definition.validate(decoded)
      else
        assert {:error, errors} = Definition.validate(d)
        assert Enum.any?(errors, &String.starts_with?(&1, "modelo.capabilities"))
        assert Enum.any?(errors, &String.contains?(&1, "participants"))
        assert Definition.validate(decoded) == {:error, errors}
      end
    end
  end

  test "portable capability metadata agrees with the closed versioned dependency/conflict registry" do
    catalogue =
      File.read!(Application.app_dir(:instantflow, "priv/templates/capabilities-1.0.json"))
      |> Jason.decode!()

    expected =
      Enum.map(Capabilities.descriptors(), fn descriptor ->
        descriptor
        |> Map.take([:id, :version, :dependencies, :conflicts])
        |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
      end)

    assert catalogue["capability_contracts"] == expected
    assert catalogue["capabilities"] == Capabilities.supported()
  end

  test "all supported additive subsets publish and execute their ordinary or resource lifecycle without legacy defaults" do
    admin = staff_fixture()
    clerk = staff_fixture("staff")

    bindings = %{
      "roles" => %{"requester" => ["admin", "staff"], "reviewer" => ["admin"]},
      "departments" => %{"responsible" => admin.department_id}
    }

    for {capabilities, index} <- subsets() |> Enum.filter(&supported?/1) |> Enum.with_index() do
      d = definition(capabilities) |> Map.put("template_key", "additive_#{index}")
      version = BuilderFixtures.install(admin, d, bindings)

      {id, session} =
        if "operations" in capabilities do
          {:ok, resource} = op(clerk, version, "add_resource", %{"name" => "Recurso sintético"})

          {:ok, session} =
            op(clerk, version, "open_session", %{
              "resource_id" => resource["id"],
              "responsible_actor" => "Operador",
              "business_date" => Operations.today(clerk)
            })

          {Operations.visit(clerk, session["id"], version.workflow_id).session.ticket_id,
           session["id"]}
        else
          {:ok, created} =
            WorkflowRuntime.command(clerk, %{
              "operation" => "create",
              "workflow_id" => version.workflow_id,
              "key" => Ecto.UUID.generate()
            })

          {created["ticket_id"], nil}
        end

      {:ok, _} =
        Instantflow.FinanceFixtures.save(clerk, id, "request", %{
          "summary" => "Semântica explícita"
        })

      if session do
        {:ok, _} =
          op(admin, version, "settle", %{
            "session_id" => session,
            "expected_total" => 0,
            "payment_method" => "cash"
          })

        assert Operations.visit(admin, session, version.workflow_id).session.status == "settled"
      else
        assert {:ok, _} = Instantflow.WorkflowFixtures.transition(admin, id, "complete")
      end

      assert {:ok, %{ticket: %{stage: "closed"}}} = WorkflowRuntime.get(admin, id)
    end
  end

  defp definition(capabilities) do
    d =
      Templates.starter("capability_matrix", "Matriz de capacidades")
      |> Map.put("capabilities", capabilities)

    if "operations" in capabilities do
      Map.put(d, "interface", %{
        "pages" => [
          %{
            "key" => "overview",
            "label" => "Trabalho",
            "blocks" => ["records", "resources", "batches", "settlement"]
          }
        ],
        "operations" => OperationalContract.defaults(),
        "lifecycle" => %{"close_transition" => "complete"}
      })
    else
      d
    end
  end

  defp subsets,
    do:
      Enum.reduce(tl(Capabilities.supported()), [["core"]], fn id, sets ->
        sets ++ Enum.map(sets, &(&1 ++ [id]))
      end)

  defp supported?(capabilities),
    do: "communications" not in capabilities or "participants" in capabilities

  defp op(actor, version, name, params),
    do:
      Operations.command(
        actor,
        Map.merge(params, %{
          "operation" => name,
          "workflow_id" => version.workflow_id,
          "key" => Ecto.UUID.generate()
        })
      )
end
