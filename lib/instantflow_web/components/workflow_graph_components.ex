defmodule InstantflowWeb.WorkflowGraphComponents do
  use InstantflowWeb, :html

  attr :graph_width, :integer, required: true
  attr :graph_height, :integer, required: true
  attr :streams, :map, required: true
  attr :current_stage, :string, default: nil

  def workflow_graph(assigns) do
    ~H"""
    <div id="graph-focus-controller" phx-hook="WorkflowGraph" phx-update="ignore" hidden></div>
    <div
      id="workflow-graph-viewport"
      class="workflow-graph"
      tabindex="0"
      role="region"
      aria-label="Diagrama do fluxo com rolagem"
    >
      <svg
        id="workflow-graph"
        viewBox={"0 0 #{@graph_width} #{@graph_height}"}
        style={"min-width: #{max(840, @graph_width)}px"}
        role="img"
        aria-labelledby="workflow-graph-title"
      >
        <title id="workflow-graph-title">
          Etapas e transições; descrições completas na lista de etapas
        </title><defs>
          <marker
            id="workflow-arrow"
            viewBox="0 0 10 10"
            refX="9"
            refY="5"
            markerWidth="6"
            markerHeight="6"
            orient="auto-start-reverse"
          >
            <path d="M 0 0 L 10 5 L 0 10 z" />
          </marker>
        </defs>
        <g id="graph-edges" phx-update="stream">
          <g
            :for={{id, edge} <- @streams.graph_edges}
            id={id}
            class={[
              "graph-connection",
              edge.secondary? && "secondary",
              edge.dimmed? && "dimmed"
            ]}
          >
            <title>{edge.title}</title><path
              d={edge.path}
              fill="none"
              class="graph-edge"
              marker-end="url(#workflow-arrow)"
            />
            <text
              x={edge.label_x}
              y={edge.label_y}
              text-anchor={edge.anchor}
              class="graph-edge-label"
            >
              {edge.label}
            </text>
          </g>
        </g>
        <g id="graph-nodes" phx-update="stream">
          <g
            :for={{id, node} <- @streams.graph_nodes}
            id={id}
            class={[
              "graph-stage",
              node.focused? && "focused",
              node.dimmed? && "dimmed",
              node.id == @current_stage && "current"
            ]}
            aria-current={if node.id == @current_stage, do: "step"}
            data-stage={node.id}
          >
            <title>{node.label}</title>
            <rect x={node.x} y={node.y} width="220" height="68" rx="10" class="graph-node" /><text
              x={node.x + 16}
              y={node.y + 29}
            >
              {if String.length(node.label) > 25,
                do: String.slice(node.label, 0, 24) <> "…",
                else: node.label}
            </text><text x={node.x + 16} y={node.y + 49} class="graph-note">
              {cond do
                node.id == @current_stage -> "Etapa atual"
                node.focused? -> "Em inspeção"
                true -> ""
              end} {if node.initial, do: "· Inicial"} {if node.terminal, do: "· Final"}
            </text>
          </g>
        </g>
      </svg>
    </div>
    """
  end
end
