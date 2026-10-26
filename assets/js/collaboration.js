// Connection state is advisory; every command is authorized and revision-checked by the server.
export const Collaboration = {
  mounted() {
    this.ready = true
    this.el.setAttribute("role", "status")
    this.el.textContent = "Conexão ativa. Alterações só são salvas após confirmação."
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
    this.el.textContent = "Conexão interrompida. Rascunhos nesta aba ainda não enviados permanecem locais."
    document.querySelectorAll("[data-authoritative]").forEach(button => {
      button.disabled = true
    })
  },
  reconnected() {
    this.el.textContent = "Reconectando: conferindo os dados atuais antes de liberar ações…"
    // Reconcile before allowing commands; never replay a mutation on reconnect.
    this.pushEvent("reconcile", {}, () => {
      this.ready = true
      this.el.textContent = "Conexão restabelecida. Confira os estados de cada formulário."
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
