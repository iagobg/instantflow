defmodule Instantflow.Calculations.Demo do
  @moduledoc "Reviewable synthetic trip example. Reading this source never executes Python."
  alias Instantflow.WorkflowCatalog.Templates
  @external_resource Path.expand("../../../priv/calculations/field_trip.py", __DIR__)
  @source File.read!(@external_resource)
  def attributes(runtime) do
    input = %{
      "participants" => integer(1, 500),
      "capacity" => integer(1, 100),
      "distance_km" => integer(0, 2000),
      "base_cents" => integer(0, 10_000_000),
      "rate_cents" => integer(0, 100_000),
      "admission_cents" => integer(0, 1_000_000)
    }

    output =
      Map.new(
        ~w(vehicles transport_cents admission_cents total_cents),
        &{&1, integer(0, 1_000_000_000)}
      )

    %{
      "key" => "field_trip_quote",
      "runtime" => runtime,
      "source" => @source,
      "input_schema" => input,
      "output_schema" => output,
      "allowed_roles" => ["admin", "staff"],
      "fixtures" => [
        %{
          "input" => %{
            "participants" => 81,
            "capacity" => 40,
            "distance_km" => 120,
            "base_cents" => 50_000,
            "rate_cents" => 250,
            "admission_cents" => 2000
          },
          "output" => %{
            "vehicles" => 3,
            "transport_cents" => 240_000,
            "admission_cents" => 162_000,
            "total_cents" => 402_000
          }
        }
      ]
    }
  end

  def definition(key, digest) do
    d = Templates.starter("field_trip_calculation", "Cotação de passeio · demonstração")
    [request] = d["sections"]
    inputs = attributes("")["input_schema"] |> Map.keys() |> Enum.sort()
    outputs = attributes("")["output_schema"] |> Map.keys() |> Enum.sort()
    request = request |> Map.put("fields", Enum.map(inputs, &input_field/1))

    quotation =
      request
      |> Map.put("key", "quotation")
      |> Map.put("label", "Cotação calculada")
      |> Map.put("fields", Enum.map(outputs, &field/1))
      |> Map.update!("access", fn access -> Enum.map(access, &Map.put(&1, "edit_stages", [])) end)

    spec = %{
      "script" => key,
      "digest" => digest,
      "inputs" => Map.new(inputs, &{&1, "request." <> &1}),
      "outputs" => Map.new(outputs, &{&1, "quotation." <> &1})
    }

    common = %{
      "required_fields" => [],
      "require_reason" => false,
      "kind" => "forward",
      "actions" => [],
      "actors" => [%{"role" => "requester", "scope" => "requester"}]
    }

    d
    |> Map.put("sections", [request, quotation])
    |> Map.put("views", [])
    |> Map.put("stages", [
      %{"key" => "draft", "label" => "Em preparação", "initial" => true, "terminal" => false},
      %{
        "key" => "waiting",
        "label" => "Aguardando cotação",
        "initial" => false,
        "terminal" => false
      },
      %{"key" => "closed", "label" => "Cotação revisada", "initial" => false, "terminal" => true}
    ])
    |> Map.put("transitions", [
      Map.merge(common, %{
        "key" => "calculate",
        "label" => "Calcular cotação",
        "from" => "draft",
        "to" => "waiting",
        "calculation" => spec
      }),
      Map.merge(common, %{
        "key" => "review",
        "label" => "Confirmar revisão da cotação",
        "from" => "waiting",
        "to" => "closed",
        "requires_calculation" => "calculate"
      }),
      Map.merge(common, %{
        "key" => "revise",
        "label" => "Revisar entradas",
        "from" => "waiting",
        "to" => "draft",
        "kind" => "correction",
        "require_reason" => true
      }),
      Map.merge(common, %{
        "key" => "cancel",
        "label" => "Cancelar cotação",
        "from" => "waiting",
        "to" => "closed",
        "kind" => "cancellation",
        "require_reason" => true
      })
    ])
  end

  defp integer(min, max), do: %{"type" => "integer", "min" => min, "max" => max}

  defp input_field("admission_cents"),
    do: %{
      "key" => "admission_cents",
      "label" => "Ingresso por participante (centavos)",
      "type" => "integer"
    }

  defp input_field(key), do: field(key)
  defp field(key), do: %{"key" => key, "label" => label(key), "type" => "integer"}
  defp label("participants"), do: "Participantes"
  defp label("capacity"), do: "Lugares por veículo"
  defp label("distance_km"), do: "Distância de ida e volta (km)"
  defp label("base_cents"), do: "Preço base por veículo (centavos)"
  defp label("rate_cents"), do: "Preço por km e veículo (centavos)"
  defp label("vehicles"), do: "Quantidade de veículos"
  defp label("transport_cents"), do: "Transporte (centavos)"
  defp label("admission_cents"), do: "Ingressos (centavos)"
  defp label("total_cents"), do: "Total (centavos)"
end
