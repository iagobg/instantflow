// Pan only the diagram when a stage is selected; LiveView owns its SVG and form state.
export const WorkflowGraph = {
  mounted() {
    this.handleEvent("workflow-graph-focus", ({stage}) => {
      const viewport = document.getElementById("workflow-graph-viewport")
      const node = Array.from(document.querySelectorAll("#graph-nodes [data-stage]"))
        .find(element => element.dataset.stage === stage)
      if (!viewport) return
      if (!node) {
        viewport.scrollTo({left: 0, top: 0})
        return
      }
      const box = node.getBoundingClientRect()
      const frame = viewport.getBoundingClientRect()
      viewport.scrollTo({
        left: Math.max(0, viewport.scrollLeft + box.left - frame.left - (viewport.clientWidth - box.width) / 2),
        top: Math.max(0, viewport.scrollTop + box.top - frame.top - (viewport.clientHeight - box.height) / 2),
        behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth",
      })
    })
  },
}
