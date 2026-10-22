// Pure local matching: typing never pushes a LiveView event or submits the form.
export const normalizeProductSearch = text => text.normalize("NFD").replace(/\p{M}/gu, "").toLocaleLowerCase("pt-BR").trim()

export const ProductPicker = {
  mounted() {
    this.input = this.el.querySelector("#product-query")
    this.value = this.el.querySelector("#item_product_id")
    this.revision = this.el.querySelector("#item_product_revision")
    this.list = this.el.querySelector("#product-suggestions")
    this.status = this.el.querySelector("#product-selection-status")
    this.source = document.getElementById(this.el.dataset.source)
    this.products = []
    this.matches = []
    this.index = 0
    this.selected = null
    this.readProducts = () => {
      this.products = Array.from(this.source.children, node => ({...node.dataset}))
      if (this.selected && !this.products.some(p => p.productId === this.selected.productId && p.revision === this.selected.revision)) {
        this.clearSelection()
        this.status.textContent = "O catálogo mudou. Selecione o produto novamente."
      }
      if (document.activeElement === this.input) this.renderMatches()
    }
    this.clearSelection = () => {
      this.selected = null
      this.value.value = ""
      this.revision.value = ""
    }
    this.hide = () => {
      this.list.hidden = true
      this.input.setAttribute("aria-expanded", "false")
      this.input.removeAttribute("aria-activedescendant")
    }
    this.choose = product => {
      this.selected = product
      this.value.value = product.productId
      this.revision.value = product.revision
      this.input.value = product.name
      this.status.textContent = "Selecionado: " + product.name + " · " + this.price(product.price) + " · " + product.destination
      this.hide()
      const quantity = document.getElementById("item_quantity")
      quantity.focus()
      quantity.select()
    }
    this.price = cents => new Intl.NumberFormat("pt-BR", {style: "currency", currency: "BRL"}).format(Number(cents) / 100)
    this.renderMatches = () => {
      const query = normalizeProductSearch(this.input.value)
      this.matches = this.products.filter(p => normalizeProductSearch(p.name + " " + p.category).includes(query)).slice(0, 20)
      this.index = Math.min(this.index, Math.max(0, this.matches.length - 1))
      this.list.replaceChildren()
      for (const [index, product] of this.matches.entries()) {
        const item = document.createElement("li")
        const option = document.createElement("button")
        option.type = "button"
        option.id = "product-option-" + product.productId
        option.setAttribute("role", "option")
        option.setAttribute("aria-selected", String(index === this.index))
        option.tabIndex = -1
        option.textContent = product.name + " · " + this.price(product.price) + " · " + product.destination
        option.addEventListener("mousedown", event => event.preventDefault())
        option.addEventListener("click", () => this.choose(product))
        item.append(option)
        this.list.append(item)
      }
      this.list.hidden = false
      this.input.setAttribute("aria-expanded", "true")
      if (this.matches.length) {
        this.input.setAttribute("aria-activedescendant", "product-option-" + this.matches[this.index].productId)
        this.status.textContent = this.matches.length + " opção(ões). Enter seleciona; setas navegam."
      } else {
        this.input.removeAttribute("aria-activedescendant")
        this.status.textContent = "Nenhum produto disponível para esta busca."
      }
    }
    this.onInput = () => { this.clearSelection(); this.index = 0; this.renderMatches() }
    this.onKey = event => {
      if (event.key === "Enter") {
        event.preventDefault()
        if (this.list.hidden) this.renderMatches()
        if (this.matches.length) this.choose(this.matches[this.index])
      } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault()
        this.index = Math.max(0, Math.min(this.matches.length - 1, this.index + (event.key === "ArrowDown" ? 1 : -1)))
        this.renderMatches()
      } else if (event.key === "Escape") {
        event.preventDefault()
        this.hide()
      }
    }
    this.onFocus = () => { if (!this.selected) this.renderMatches() }
    this.onBlur = () => this.hide()
    this.input.addEventListener("input", this.onInput)
    this.input.addEventListener("keydown", this.onKey)
    this.input.addEventListener("focus", this.onFocus)
    this.input.addEventListener("blur", this.onBlur)
    this.observer = new MutationObserver(this.readProducts)
    this.observer.observe(this.source, {childList: true, subtree: true, attributes: true})
    this.readProducts()
  },
  destroyed() {
    this.observer.disconnect()
    this.input.removeEventListener("input", this.onInput)
    this.input.removeEventListener("keydown", this.onKey)
    this.input.removeEventListener("focus", this.onFocus)
    this.input.removeEventListener("blur", this.onBlur)
  }
}
