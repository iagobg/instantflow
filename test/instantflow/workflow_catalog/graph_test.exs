defmodule Instantflow.WorkflowCatalog.GraphTest do
  use ExUnit.Case, async: true
  import Instantflow.WorkflowFixtures
  alias Instantflow.WorkflowCatalog.Graph

  test "an empty stage collection produces an empty diagram" do
    graph = Graph.layout(%{"stages" => [], "transitions" => []})
    assert graph.nodes == []
    assert graph.edges == []
    assert graph.width > 0 and graph.height > 0
  end

  test "main stages align vertically and alternate routes have distinct orthogonal paths" do
    graph = Graph.layout(definition_fixture())
    nodes = Map.new(graph.nodes, &{&1.id, &1})
    assert nodes["draft"].x == nodes["review"].x
    assert nodes["review"].x == nodes["approved"].x
    assert nodes["draft"].y < nodes["review"].y
    assert nodes["review"].y < nodes["approved"].y
    assert nodes["correction"].x > nodes["approved"].x
    assert length(Enum.uniq_by(graph.edges, & &1.path)) == length(graph.edges)
    assert Enum.all?(graph.edges, &(not String.contains?(&1.path, " C ")))

    assert Enum.all?(
             graph.nodes,
             &(&1.x >= 0 and &1.y >= 0 and &1.x + 220 < graph.width and &1.y + 68 < graph.height)
           )
  end

  test "focus highlights incident paths and incomplete draft references do not create phantom edges" do
    d = definition_fixture()
    graph = Graph.layout(d, "review")
    active = graph.edges |> Enum.reject(& &1.dimmed?) |> Enum.map(& &1.id)
    assert "submit" in active
    assert "approve" in active
    refute "cancel_draft" in active
    assert Enum.find(graph.nodes, &(&1.id == "review")).focused?
    refute Enum.find(graph.nodes, &(&1.id == "approved")).dimmed?
    malformed = put_in(d, ["transitions", Access.at(0), "to"], "missing")
    refute Enum.any?(Graph.layout(malformed).edges, &(&1.id == "submit"))
  end
end
