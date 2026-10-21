defmodule Instantflow.CalculationFixtures do
  alias Instantflow.{Access, Calculations, Repo, WorkflowCatalog}
  alias Instantflow.Calculations.{Catalogue, Runner}
  import Instantflow.WorkflowFixtures

  def execute(request) do
    send(self(), {:calculation_request, Map.drop(request, ["source"])})
    input = request["input"]

    output =
      if input["capacity"] do
        vehicles = div(input["participants"] + input["capacity"] - 1, input["capacity"])
        transport = vehicles * (input["base_cents"] + input["distance_km"] * input["rate_cents"])
        admission = input["participants"] * input["admission_cents"]

        %{
          "vehicles" => vehicles,
          "transport_cents" => transport,
          "admission_cents" => admission,
          "total_cents" => transport + admission
        }
      else
        %{"total" => input["participants"] * 100}
      end

    {:ok,
     Map.take(request, ~w(organization_id run_id fence))
     |> Map.merge(%{"status" => "succeeded", "output" => output})}
  end

  def attrs do
    %{
      "key" => "trip_cost",
      "source" => "def calculate(inputs):\n    return {'total': inputs['participants'] * 100}\n",
      "runtime" => String.duplicate("a", 64),
      "input_schema" => %{"participants" => %{"type" => "integer", "min" => 1, "max" => 500}},
      "output_schema" => %{"total" => %{"type" => "integer", "min" => 0, "max" => 1_000_000_000}},
      "allowed_roles" => ["staff"],
      "fixtures" => [%{"input" => %{"participants" => 81}, "output" => %{"total" => 8100}}]
    }
  end

  def fixture do
    f = workflow_fixture()

    for role <- ~w(python_author python_reviewer python_source python_binder) do
      {:ok, _} = Access.grant(f.admin, f.admin.id, f.admin.department_id, role)
    end

    {:ok, _} = Access.grant(f.admin, f.requester.id, f.requester.department_id, "python_execute")
    {:ok, script} = Catalogue.register(f.admin, attrs())
    {:ok, :verified} = Catalogue.verify(f.admin, script.id)
    {:ok, :ok} = Catalogue.activate(f.admin, script.id, true)
    [request] = f.definition["sections"]

    request =
      request
      |> Map.put("fields", [
        %{"key" => "participants", "label" => "Participantes", "type" => "integer"}
      ])
      |> Map.update!("access", fn list ->
        Enum.map(list, &Map.put(&1, "edit_stages", ["draft", "review"]))
      end)

    output =
      request
      |> Map.put("key", "quotation")
      |> Map.put("label", "Cotação calculada")
      |> Map.put("fields", [
        %{"key" => "total", "label" => "Total (centavos)", "type" => "money", "currency" => "BRL"}
      ])
      |> Map.update!("access", fn list -> Enum.map(list, &Map.put(&1, "edit_stages", [])) end)

    spec = %{
      "script" => script.key,
      "digest" => script.digest,
      "inputs" => %{"participants" => "request.participants"},
      "outputs" => %{"total" => "quotation.total"}
    }

    definition =
      f.definition
      |> Map.put("sections", [request, output])
      |> Map.put("views", [])
      |> Map.update!("transitions", fn transitions ->
        Enum.map(transitions, fn t ->
          t =
            t |> Map.put("actions", []) |> Map.put("guard", nil) |> Map.put("required_fields", [])

          case t["key"] do
            "submit" -> Map.put(t, "calculation", spec)
            "approve" -> Map.put(t, "requires_calculation", "submit")
            _ -> t
          end
        end)
      end)

    {:ok, version} = WorkflowCatalog.publish(f.admin, definition, f.bindings, 1)
    f = %{f | version: version, definition: definition}
    id = create_ticket(f)
    {:ok, _} = save(f.requester, id, %{"participants" => 81})
    {:ok, _} = transition(f.requester, id, "submit")
    %{f: f, id: id, script: script}
  end

  def claim(org \\ 1) do
    {:ok, {run, script}} = Calculations.claim(org)
    request = Runner.request(script, run.snapshot, run.id, run.fence)
    %{run: run, request: request}
  end

  def response(request, output \\ %{"total" => 8100}) do
    {:ok,
     Map.take(request, ~w(organization_id run_id fence))
     |> Map.merge(%{"status" => "succeeded", "output" => output})}
  end

  def switch(enabled) do
    Repo.query!("UPDATE calculation_switch SET enabled = $1, generation = generation + 1", [
      enabled
    ])
  end
end
