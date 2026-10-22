export const OperationsPrint = {
  mounted() {
    this.handleEvent("operations:print", () => {
      requestAnimationFrame(() => window.print())
    })
  }
}
