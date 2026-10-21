// Connection state is advisory; every command is authorized and revision-checked by the server.
export const Collaboration = {
  mounted() {
    this.ready = true
    this.sync = () => {
      if (this.ready) this.pushEvent("heartbeat", {})
    }
    this.timer = setInterval(this.sync, 15000)
    this.blockOffline = event => {
      const command = event.type === "submit"
        ? event.target.querySelector("[data-authoritative]")
        : event.target.closest("[data-authoritative]")
      if (!this.ready && command) {
        event.preventDefault()
        event.stopImmediatePropagation()
      }
    }
    document.addEventListener("submit", this.blockOffline, true)
    document.addEventListener("click", this.blockOffline, true)
  },
  disconnected() {
    this.ready = false
    document.querySelectorAll("[data-authoritative]").forEach(button => {
      button.disabled = true
    })
  },
  reconnected() {
    // Reconcile before allowing commands; never replay a mutation on reconnect.
    this.pushEvent("reconcile", {}, () => {
      this.ready = true
      document.querySelectorAll("[data-authoritative]").forEach(button => {
        button.disabled = button.dataset.blocked === "true"
      })
    })
  },
  destroyed() {
    clearInterval(this.timer)
    document.removeEventListener("submit", this.blockOffline, true)
    document.removeEventListener("click", this.blockOffline, true)
  }
}
