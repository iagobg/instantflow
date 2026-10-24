# Run serially: MIX_ENV=test mix run scripts/benchmark_stage_boards.exs OUTPUT.json
# Every scenario rolls back in the SQL sandbox; never targets a serving demo.
if Mix.env() != :test, do: raise("This benchmark requires MIX_ENV=test")

unless String.ends_with?(Instantflow.Repo.config()[:database], "_test"),
  do: raise("This benchmark requires an explicitly configured test database")

defmodule StageBoardBenchmark do
  import Ecto.Query
  import Instantflow.WorkflowFixtures
  alias Instantflow.{Access, Identity, Repo, Tenant, WorkflowCatalog}
  alias Instantflow.WorkflowCatalog.{Views, Workspaces}
  alias Instantflow.WorkflowRuntime.{BoardVersions, ConfiguredQueries, Projections}

  def query_event(_, _, metadata, owner) do
    bytes =
      case metadata.result do
        {:ok, %{rows: rows}} when is_list(rows) -> byte_size(:erlang.term_to_binary(rows))
        _ -> 0
      end

    send(owner, {:query_bytes, bytes})
  end

  def run do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)

    for shape <- ["narrow", "wide"], pins <- [1, 10, 100] do
      owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)

      try do
        f = fixture(shape, pins)

        operations = [
          {"legacy_discovery", fn -> legacy(f) end},
          {"compact_discovery",
           fn ->
             Tenant.read(f.requester, &BoardVersions.discover(&1, f.version.workflow_id, "board"))
           end},
          {"board_refresh",
           fn -> Views.board(f.requester, f.version.workflow_id, "board", %{}) end}
        ]

        measurements =
          Map.new(operations, fn {name, operation} ->
            for _ <- 1..2, do: operation.()
            samples = for _ <- 1..9, do: measure(operation)

            {name,
             %{
               samples: samples,
               p50_ms: percentile(samples, 0.5),
               p95_ms: percentile(samples, 0.95),
               p99_ms: percentile(samples, 0.99)
             }}
          end)

        result = Views.board(f.requester, f.version.workflow_id, "board", %{})
        expected = if rem(pins, 2) == 0, do: div(pins, 2) + 1, else: div(pins + 1, 2)

        if result.version_total != expected or result.total != 1 or result.loaded != 1,
          do: raise("Authorization/state mismatch in benchmark")

        %{
          shape: shape,
          populated_pins: pins,
          fields_per_definition: if(shape == "wide", do: 102, else: 2),
          authorized_pins: expected,
          hidden_records: pins - expected + 1,
          measurements: measurements
        }
      after
        Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
      end
    end
  end

  defp fixture(shape, pins) do
    f = workflow_fixture()
    stranger = Instantflow.IdentityFixtures.staff_fixture("staff")

    for actor <- [f.requester, stranger],
        do: Access.grant(f.admin, actor.id, actor.department_id, "teacher")

    bindings =
      f.bindings
      |> put_in(["roles", "requester"], ["teacher"])
      |> put_in(["roles", "reviewer"], ["head"])

    f = %{
      f
      | bindings: bindings,
        requester: Identity.scope(f.requester.user_id, f.requester.organization_id)
    }

    stranger = Identity.scope(stranger.user_id, stranger.organization_id)

    Enum.reduce(1..pins, f, fn index, current ->
      definition =
        f.definition
        |> Map.put("description", "Distinct populated pin #{index}")
        |> Map.put("views", [
          %{
            "key" => "board",
            "label" => "Board",
            "type" => "board",
            "columns" => ["stage", "request.summary"]
          }
        ])
        |> Map.update!("sections", fn [section] ->
          extra =
            if shape == "wide",
              do:
                for(
                  n <- 1..100,
                  do: %{
                    "key" => "field#{n}",
                    "label" => "Pin #{index} " <> String.duplicate("wide ", 30) <> to_string(n),
                    "type" => "short_text"
                  }
                ),
              else: []

          [Map.update!(section, "fields", &(&1 ++ extra))]
        end)

      {:ok, version} =
        WorkflowCatalog.publish(f.admin, definition, bindings, current.version.number)

      next = %{current | version: version, definition: definition}
      actor = if rem(index, 2) == 1 or index == pins, do: f.requester, else: stranger
      create_ticket(%{next | requester: actor})
      # A hidden record even in the one-pin scenario, sharing the selected pin.
      if index == pins, do: create_ticket(%{next | requester: stranger})
      next
    end)
  end

  defp legacy(f) do
    Tenant.read(f.requester, fn scope ->
      versions = Projections.versions(%{"workflow_id" => f.version.workflow_id}, :full)
      latest = Workspaces.get(scope, f.version.workflow_id)
      versions = Enum.uniq_by([latest | versions], & &1.id)

      versions =
        Enum.filter(versions, fn v ->
          view = ConfiguredQueries.view(v, "board")
          view && view["type"] == "board" && Projections.visible_view?(scope, v, view)
        end)

      base = Projections.view_query(scope, versions, "board")
      Repo.all(from t in base, distinct: t.workflow_version_id, select: t.workflow_version_id)
    end)
  end

  defp measure(operation) do
    id = {__MODULE__, make_ref()}
    :ok = :telemetry.attach(id, [:instantflow, :repo, :query], &__MODULE__.query_event/4, self())
    {micros, _} = :timer.tc(operation)
    :telemetry.detach(id)
    %{latency_ms: micros / 1000, decoded_result_bytes: drain(0)}
  end

  defp drain(total) do
    receive do
      {:query_bytes, bytes} -> drain(total + bytes)
    after
      0 -> total
    end
  end

  defp percentile(samples, quantile) do
    samples
    |> Enum.map(& &1.latency_ms)
    |> Enum.sort()
    |> Enum.at(ceil(length(samples) * quantile) - 1)
  end
end

{revision, 0} = System.cmd("git", ["rev-parse", "HEAD"])

report = %{
  baseline_revision: String.trim(revision),
  source_sha256:
    Map.new(
      [
        "lib/instantflow/workflow_runtime/board_versions.ex",
        "lib/instantflow/workflow_runtime/stage_boards.ex",
        "lib/instantflow/workflow_runtime/projections.ex",
        "scripts/benchmark_stage_boards.exs"
      ],
      fn path -> {path, Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)} end
    ),
  working_tree: "Review follow-up: BoardVersions compact batched admission",
  environment: %{
    elixir: System.version(),
    otp: to_string(:erlang.system_info(:otp_release)),
    schedulers: System.schedulers_online(),
    database: "isolated SQL sandbox on local PostgreSQL 16"
  },
  measurement:
    "Serial in-process reads with payload instrumentation included in latency; two warmups and nine raw samples. Bytes are uncompressed Erlang external-term encoding of decoded database result rows, a payload proxy, not PostgreSQL wire bytes or memory residency. p95/p99 are nearest-rank and equal the maximum at nine samples. No HTTP, browser, k6 or concurrent capacity claim.",
  scenarios: StageBoardBenchmark.run()
}

output = List.first(System.argv()) || raise("Pass an output JSON path")
File.write!(output, Jason.encode!(report, pretty: true) <> "\n")
IO.puts("Board benchmark saved: " <> output)
