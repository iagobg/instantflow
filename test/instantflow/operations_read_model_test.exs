defmodule Instantflow.OperationsReadModelTest do
  use Instantflow.DataCase, async: true
  import Instantflow.OperationsFixtures
  alias Instantflow.Operations

  test "workspace pages bound fetched rows while whole-day aggregates retain every session and cancellation" do
    f = operations_fixture()
    date = Operations.today(f.actor)
    version = Operations.workspace(f.actor, date).version

    visits =
      for n <- 1..60 do
        {:ok, _} =
          operation(f.actor, "save_product", %{
            "workflow_id" => version.workflow_id,
            "name" => "Extra #{n}",
            "category" => "Geral",
            "price" => 100,
            "destination" => "Cozinha"
          })

        {:ok, r} =
          operation(f.actor, "add_resource", %{
            "workflow_id" => version.workflow_id,
            "name" => "Recurso #{n}"
          })

        {:ok, s} =
          operation(f.actor, "open_session", %{
            "workflow_id" => version.workflow_id,
            "resource_id" => r["id"],
            "responsible_actor" => "Operador #{n}",
            "business_date" => date
          })

        s["id"]
      end

    {:ok, _} =
      operation(f.actor, "submit_batch", %{
        "workflow_id" => version.workflow_id,
        "session_id" => hd(visits),
        "lines" => [item(f.actor, f.soup, 2), item(f.actor, f.asado)]
      })

    {:ok, %{"ids" => [cancelled]}} =
      operation(f.actor, "submit_batch", %{
        "workflow_id" => version.workflow_id,
        "session_id" => Enum.at(visits, 1),
        "lines" => [item(f.actor, f.soup)]
      })

    {:ok, _} =
      operation(f.actor, "cancel_batch", %{
        "workflow_id" => version.workflow_id,
        "batch_id" => cancelled,
        "reason" => "Cancelamento sintético"
      })

    handler = "operations-read-#{Ecto.UUID.generate()}"
    :ok = :telemetry.attach(handler, [:instantflow, :repo, :query], &__MODULE__.capture/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)
    data = Operations.workspace(f.actor, date, version.workflow_id)
    events = events([])
    assert Enum.max(Enum.map(events, & &1.rows)) <= 25
    assert length(events) < 35
    assert length(data.products) == 25
    assert length(data.resources) == 25
    assert length(data.sessions) <= 25
    assert data.pagination.products.total == 62
    assert data.pagination.resources.total == 61
    assert data.report.open_count == 60
    assert data.report.open_total == 13100
    assert data.report.cancellations == 2550
    assert Enum.sum(Enum.map(data.report.consumption, & &1.quantity)) == 3
    assert data.report.sales == 0

    last =
      Operations.workspace(f.actor, date, version.workflow_id, nil, %{
        "products_page" => "999999999",
        "resources_page" => "3"
      })

    assert last.pagination.products.page == 3
    assert length(last.products) == 12
    assert length(last.resources) == 11

    refute MapSet.intersection(
             MapSet.new(data.products, & &1.id),
             MapSet.new(last.products, & &1.id)
           )
           |> MapSet.size() > 0

    filtered =
      Operations.workspace(f.actor, date, version.workflow_id, nil, %{
        "products_query" => "sopa",
        "resources_query" => "Recurso 60"
      })

    assert Enum.map(filtered.products, & &1.id) == [f.soup]
    assert filtered.pagination.resources.total == 1
    assert length(filtered.sessions) == 1
    assert filtered.report.open_count == 60
  end

  test "paged reports retain the complete immutable closing consumption snapshot" do
    f = operations_fixture()
    version = Operations.workspace(f.actor, Operations.today(f.actor)).version

    products =
      for n <- 1..30 do
        {:ok, product} =
          operation(f.actor, "save_product", %{
            "name" => "Snapshot #{n}",
            "category" => "Snapshot",
            "price" => 100,
            "destination" => "Cozinha"
          })

        %{
          "product_id" => product["id"],
          "product_revision" => Repo.get!(Instantflow.Operations.Product, product["id"]).revision,
          "quantity" => 1
        }
      end

    id = open_visit(f)

    {:ok, %{"ids" => [batch]}} =
      operation(f.actor, "submit_batch", %{"session_id" => id, "lines" => products})

    {:ok, _} = operation(f.actor, "handoff", %{"batch_id" => batch})

    {:ok, _} =
      operation(f.actor, "settle", %{
        "session_id" => id,
        "expected_total" => 3000,
        "payment_method" => "cash"
      })

    date = Operations.today(f.actor)
    {:ok, _} = operation(f.actor, "close_day", %{"business_date" => date})
    first = Operations.workspace(f.actor, date, version.workflow_id).report

    second =
      Operations.workspace(f.actor, date, version.workflow_id, nil, %{"consumption_page" => 2}).report

    assert length(first.consumption) == 25 and length(second.consumption) == 5
    assert first.sales == 3000 and first.settled_count == 1
    assert first.pagination.total == 30

    close =
      Repo.get_by!(Instantflow.Operations.DayClose,
        workflow_id: version.workflow_id,
        business_date: date
      )

    assert length(close.summary["consumption"]) == 30
    assert Enum.sum(Enum.map(close.summary["consumption"], & &1["quantity"])) == 30
    refute Map.has_key?(first.closed.summary, "consumption")
  end

  test "allowed high-price quantity totals use bigint arithmetic throughout checkout and reports" do
    f = operations_fixture()

    {:ok, product} =
      operation(f.actor, "save_product", %{
        "name" => "Máximo",
        "category" => "Geral",
        "price" => 100_000_000,
        "destination" => "Cozinha"
      })

    id = open_visit(f)

    {:ok, %{"ids" => [batch]}} =
      operation(f.actor, "submit_batch", %{
        "session_id" => id,
        "lines" => [
          %{
            "product_id" => product["id"],
            "product_revision" =>
              Repo.get!(Instantflow.Operations.Product, product["id"]).revision,
            "quantity" => 999
          }
        ]
      })

    assert Operations.visit(f.actor, id).total == 99_900_000_000

    assert Operations.workspace(f.actor, Operations.today(f.actor)).report.open_total ==
             99_900_000_000

    {:ok, _} = operation(f.actor, "handoff", %{"batch_id" => batch})

    {:ok, _} =
      operation(f.actor, "settle", %{
        "session_id" => id,
        "expected_total" => 99_900_000_000,
        "payment_method" => "pix"
      })

    assert Operations.workspace(f.actor, Operations.today(f.actor)).report.payments["pix"] ==
             99_900_000_000
  end

  def capture(_, _, %{result: {:ok, %{rows: rows}}}, owner)
      when self() == owner and is_list(rows),
      do: send(owner, {:read_query, length(rows)})

  def capture(_, _, _, _), do: :ok

  defp events(acc) do
    receive do
      {:read_query, rows} -> events([%{rows: rows} | acc])
    after
      0 -> acc
    end
  end
end
