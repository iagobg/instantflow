defmodule Instantflow.WorkflowCatalog.Graph do
  @moduledoc "Deterministic layered diagram with separate lanes for return and cancellation paths."
  @node_width 220
  @node_height 68
  @column_gap 70
  @row_gap 120

  def layout(definition, focus \\ "") do
    stages = definition["stages"]
    transitions = definition["transitions"]
    initial = Enum.find(stages, & &1["initial"]) || hd(stages)
    forward = Enum.reject(transitions, &(&1["kind"] in ~w(cancellation resubmission reopening)))
    ranks = rank([{initial["key"], 0}], forward, %{})
    last_rank = (ranks |> Map.values() |> Enum.max(fn -> 0 end)) + 1
    ranks = Map.new(stages, &{&1["key"], Map.get(ranks, &1["key"], last_rank)})

    main_stages =
      rank([{initial["key"], 0}], Enum.filter(transitions, &(&1["kind"] == "forward")), %{})

    levels = stages |> Enum.group_by(&ranks[&1["key"]]) |> Enum.sort()
    columns = levels |> Enum.map(fn {_, list} -> length(list) end) |> Enum.max()

    returns =
      Enum.filter(
        transitions,
        &(&1["kind"] != "cancellation" and Map.has_key?(ranks, &1["to"]) and
            Map.has_key?(ranks, &1["from"]) and ranks[&1["to"]] <= ranks[&1["from"]])
      )

    detours =
      Enum.filter(
        transitions,
        &(&1["kind"] == "cancellation" or
            (Map.has_key?(ranks, &1["to"]) and Map.has_key?(ranks, &1["from"]) and
               ranks[&1["to"]] > ranks[&1["from"]] + 1))
      )

    related =
      transitions
      |> Enum.filter(&(&1["from"] == focus or &1["to"] == focus))
      |> Enum.flat_map(&[&1["from"], &1["to"]])
      |> MapSet.new()
      |> MapSet.put(focus)

    left = 70 + length(returns) * 24

    nodes =
      Enum.flat_map(levels, fn {level, list} ->
        list
        |> Enum.sort_by(&(not Map.has_key?(main_stages, &1["key"])))
        |> Enum.with_index()
        |> Enum.map(fn {stage, index} ->
          %{
            id: stage["key"],
            label: stage["label"],
            initial: stage["initial"],
            terminal: stage["terminal"],
            x: left + index * (@node_width + @column_gap),
            y: 44 + level * (@node_height + @row_gap),
            focused?: focus == stage["key"],
            dimmed?: focus != "" and not MapSet.member?(related, stage["key"])
          }
        end)
      end)

    positions = Map.new(nodes, &{&1.id, &1})
    right = left + columns * (@node_width + @column_gap) - @column_gap

    edges =
      transitions
      |> Enum.with_index()
      |> Enum.flat_map(fn {t, index} ->
        with %{x: _, y: _} = source <- positions[t["from"]],
             %{x: _, y: _} = target <- positions[t["to"]] do
          outgoing =
            Enum.filter(transitions, &(&1["from"] == t["from"] and &1["kind"] != "cancellation"))

          incoming =
            Enum.filter(transitions, &(&1["to"] == t["to"] and &1["kind"] != "cancellation"))

          sx = port(source.x, outgoing, t)
          tx = port(target.x, incoming, t)
          sy = source.y + @node_height
          ty = target.y
          secondary? = t["kind"] != "forward"

          {path, label_x, label_y, anchor} =
            cond do
              t["kind"] == "cancellation" or target.y - source.y > @node_height + @row_gap ->
                slot = Enum.find_index(detours, &(&1["key"] == t["key"]))
                lane = right + 44 + slot * 28
                y1 = sy + 24
                tx = target.x + round(@node_width * (slot + 1) / (length(detours) + 1))

                {"M #{source.x + @node_width - 18} #{sy} V #{y1} H #{lane} V #{ty - 24} H #{tx} V #{ty}",
                 source.x + @node_width + 14, y1 - 8, "start"}

              target.y <= source.y ->
                slot = Enum.find_index(returns, &(&1["key"] == t["key"]))
                lane = 24 + slot * 24

                {"M #{source.x + 18} #{sy} V #{sy + 24} H #{lane} V #{ty - 24} H #{target.x + 18} V #{ty}",
                 lane + 10, sy + 16, "start"}

              true ->
                middle = sy + 42 + rem(index, 3) * 28

                {"M #{sx} #{sy} V #{middle} H #{tx} V #{ty}",
                 if(sx == tx, do: sx + 12, else: (sx + tx) / 2), middle - 10,
                 if(sx == tx, do: "start", else: "middle")}
            end

          [
            %{
              id: t["key"],
              label: t["label"],
              path: path,
              label_x: label_x,
              label_y: label_y,
              anchor: anchor,
              secondary?: secondary?,
              dimmed?: focus != "" and t["from"] != focus and t["to"] != focus,
              title: "#{source.label} → #{target.label}: #{t["label"]}"
            }
          ]
        else
          _ -> []
        end
      end)

    %{
      nodes: nodes,
      edges: edges,
      width: max(right + 90 + length(detours) * 28, 600),
      height: Enum.max_by(nodes, & &1.y).y + @node_height + 44
    }
  end

  defp port(x, edges, transition) do
    index = Enum.find_index(edges, &(&1["key"] == transition["key"])) || 0
    x + round(@node_width * (index + 1) / (length(edges) + 1))
  end

  defp rank([], _, visited), do: visited

  defp rank([{key, level} | rest], edges, visited) do
    if Map.has_key?(visited, key) do
      rank(rest, edges, visited)
    else
      next = for edge <- edges, edge["from"] == key, do: {edge["to"], level + 1}
      rank(rest ++ next, edges, Map.put(visited, key, level))
    end
  end
end
