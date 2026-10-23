defmodule InstantflowWeb.ProcessComponents do
  @moduledoc "Reusable process block templates. Contexts and LiveViews own queries, authorization and commands."
  use InstantflowWeb, :html
  import InstantflowWeb.ProcessRoutes
  alias Instantflow.Operations

  def finance_setup_block(assigns) do
    ~H"""
    <section id="process-finance-setup" class="card">
      <h2>Configuração financeira local</h2>
      <.form
        :if={@finance_surface.can_create?}
        for={@finance_account_form}
        id="process-finance-account"
        phx-submit="finance-create-account"
      >
        <.input field={@finance_account_form[:name]} label="Nome da conta" required />
        <.input
          field={@finance_account_form[:department_id]}
          type="select"
          label="Departamento"
          options={@finance_surface.departments}
          required
        />
        <button id="process-finance-create" class="btn">Criar conta</button>
      </.form>
      <.form
        :if={@finance_surface.can_allocate?}
        for={@finance_allocation_form}
        id="process-finance-allocation"
        phx-submit="finance-allocate"
      >
        <.input
          field={@finance_allocation_form[:account_id]}
          type="select"
          label="Conta vinculada"
          options={@finance_surface.account_options}
        />
        <.input
          field={@finance_allocation_form[:amount]}
          type="number"
          label="Alocação em centavos"
          min="1"
          required
        />
        <.input field={@finance_allocation_form[:reason]} label="Motivo" required />
        <button id="process-finance-allocate" class="btn">Alocar</button>
      </.form>
    </section>
    """
  end

  def finance_summary_block(assigns) do
    ~H"""
    <section id="process-finance-summary" class="card">
      <h2>Resumo financeiro autorizado</h2>
      <p>
        {if @finance_surface.scope == "process",
          do: "Somente registros autorizados deste processo",
          else: "Total compartilhado da conta, com autorização financeira própria"}
      </p>
      <div id="process-finance-accounts" phx-update="stream">
        <article :for={{id, account} <- @streams.finance_summaries} id={id}>
          <h3>{account.name}</h3><p>Reservado: {account.reserved} · Gasto: {account.spent}</p>
          <p :if={!is_nil(account.available)}>
            Alocado: {account.allocated} · Disponível: {account.available}
          </p>
        </article>
      </div>
    </section>
    """
  end

  def records_block(assigns) do
    ~H"""
    <section id="process-records-block" class="card template-section">
      <h2>Registros</h2>
      <button
        :if={@can_create_record}
        id="create-process-record"
        class="btn primary"
        phx-click="record-create"
        phx-disable-with="Iniciando…"
      >Iniciar registro</button>
      <p :if={@record_view_options == []} id="process-record-views-empty">
        Este processo ainda não tem uma visualização de registros configurada.
      </p>
      <.form
        :if={@record_view_options != []}
        for={@record_form}
        id="process-record-filters"
        phx-submit="record-filters"
        class="operations-form"
      >
        <.input field={@record_form[:query]} label="Buscar registro" />
        <.input
          field={@record_form[:view]}
          type="select"
          label="Visualização"
          options={@record_view_options}
        />
        <.input
          field={@record_form[:stage]}
          type="select"
          label="Etapa"
          options={@record_stage_options}
          prompt="Todas"
        />
        <button id="filter-process-records" class="btn">Filtrar</button>
        <.input
          :for={filter <- @record_filter_options}
          name={"record_filter[fields][#{filter.ref}]"}
          id={"record-filter-#{filter.ref}"}
          type="select"
          label={filter.label}
          options={Enum.map(filter.values, &{to_string(&1), to_string(&1)})}
          value={get_in(@record_form.params, ["fields", filter.ref])}
          prompt="Todos"
        />
        <.input
          :if={@record_assignments?}
          field={@record_form[:assigned_to]}
          type="select"
          label="Atribuição nominal"
          prompt="Todas"
          options={[{"Minhas atribuições", "me"}, {"Sem responsável", "unassigned"}]}
        />
      </.form>
      <p id="process-record-count">{@record_total} registro(s) disponível(is)</p>
      <p id="process-urgency-status" role="status" aria-live="polite">
        {@record_urgent} registro(s) com maior urgência em aberto.
      </p>
      <div
        id="process-records"
        phx-update="stream"
        class={if @record_view_type == "board", do: "operations-tables"}
      >
        <article :for={{id, row} <- @streams.process_records} id={id} class="operations-batch">
          <h3>#{row.id} · {row.stage_label}</h3>
          <p :if={@record_view_type == "calendar"} class="calendar-date">
            {if row.date, do: row.date, else: "Sem data"}{if row.date_kind == "date",
              do: " · data civil"}
          </p>
          <p :if={row.assignment}>Responsável: {row.assignment}</p>
          <p :if={row.urgency}>Urgência: {row.urgency}</p>
          <dl>
            <div :for={column <- @record_columns}>
              <dt>{column.label}</dt><dd>{cell(row, column.key)}</dd>
            </div>
          </dl>
          <.link
            id={"open-process-record-#{row.id}"}
            navigate={
              ~p"/o/#{@current_scope.organization.slug}/processos/#{@workflow_id}/registros/#{row.id}"
            }
            class="btn"
          >Abrir registro</.link>
        </article>
      </div>
      <nav :if={@record_pages > 1} id="process-record-pagination" aria-label="Páginas de registros">
        <button
          id="process-record-previous"
          class="btn"
          phx-click="record-page"
          phx-value-page={@record_page - 1}
          disabled={@record_page <= 1}
        >Anterior</button>
        <span id="process-record-page">{@record_page} / {@record_pages}</span>
        <button
          id="process-record-next"
          class="btn"
          phx-click="record-page"
          phx-value-page={@record_page + 1}
          disabled={@record_page >= @record_pages}
        >Próxima</button>
      </nav>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :kind, :string, required: true
  attr :info, :map, required: true
  attr :label, :string, required: true
  attr :form, Phoenix.HTML.Form, required: true

  def operational_controls(assigns) do
    ~H"""
    <.form
      for={@form}
      id={@id <> "-filters"}
      phx-submit="operational-filter"
      phx-value-kind={@kind}
      class="operations-form"
    >
      <.input field={@form[:query]} id={@id <> "-query"} label={@label} maxlength="100" />
      <button id={@id <> "-filter"} class="btn">Buscar</button>
    </.form>
    <.operational_pager id={@id} kind={@kind} info={@info} />
    """
  end

  attr :id, :string, required: true
  attr :kind, :string, required: true
  attr :info, :map, required: true

  def operational_pager(assigns) do
    ~H"""
    <p id={@id <> "-count"}>{@info.total} resultado(s) · Página {@info.page} de {@info.pages}</p>
    <nav :if={@info.pages > 1} id={@id <> "-pagination"} aria-label="Páginas de resultados">
      <button
        type="button"
        class="btn"
        id={@id <> "-previous"}
        phx-click="operational-page"
        phx-value-kind={@kind}
        phx-value-page={@info.page - 1}
        disabled={@info.page <= 1}
      >Anterior</button>
      <button
        type="button"
        class="btn"
        id={@id <> "-next"}
        phx-click="operational-page"
        phx-value-kind={@kind}
        phx-value-page={@info.page + 1}
        disabled={@info.page >= @info.pages}
      >Próxima</button>
    </nav>
    """
  end

  def catalog_block(assigns) do
    ~H"""
    <details
      id="menu-setup"
      class="card"
      open={map_size(@product_catalog) == 0 || @product_id != nil}
    >
      <summary>
        <strong>Preparar {@labels["catalog"]} e {@labels["resources"]}</strong>
      </summary>
      <p>
        Cadastre nome, preço e destino antes do atendimento. Desativar retira o produto de novos pedidos; o histórico é preservado.
      </p>
      <.form
        for={@product_form}
        id="product-form"
        phx-submit="save-product"
        class="operations-form"
      >
        <.input field={@product_form[:name]} label="Produto" required maxlength="120" />
        <.input field={@product_form[:category]} label="Categoria" required maxlength="80" />
        <.input
          field={@product_form[:price]}
          label="Preço em reais"
          placeholder="25,50"
          required
          inputmode="decimal"
        />
        <.input
          field={@product_form[:destination]}
          label={@labels["destination"]}
          placeholder="Informe o destino"
          required
          maxlength="80"
        />
        <.input field={@product_form[:active]} type="checkbox" label="Disponível para pedidos" />
        <button id="save-product" class="btn primary" phx-disable-with="Salvando…">{if @product_id,
          do: "Salvar alterações",
          else: "Cadastrar produto"}</button>
        <button
          :if={@product_id}
          id="new-product"
          type="button"
          class="btn"
          phx-click="new-product"
        >Novo produto</button>
      </.form>
      <.operational_controls
        id="catalog-setup"
        kind="products"
        form={@product_search_form}
        info={@read_pages.products}
        label={"Buscar em todo o catálogo: #{@labels["catalog"]}"}
      />
      <div id="menu-products" phx-update="stream" class="operations-menu">
        <div :for={{id, product} <- @streams.products} id={id} class="operations-product">
          <strong>{product.name}</strong><span>{money(product.price)} · {product.category} · {product.destination}</span>
          <span :if={!product.active}>Indisponível</span><button
            id={"edit-product-#{product.id}"}
            class="btn"
            phx-click="edit-product"
            phx-value-id={product.id}
          >Editar</button>
        </div>
      </div>
    </details>
    """
  end

  def resources_block(assigns) do
    ~H"""
    <section class="card template-section">
      <h2>{@labels["resources"]}</h2>
      <.form
        :if={@can_configure}
        for={@resource_form}
        id="resource-form"
        phx-submit="add-resource"
        class="operations-form"
      >
        <.input
          field={@resource_form[:name]}
          label={"Número ou nome: #{@labels["resource"]}"}
          placeholder={@labels["resource"]}
          required
          maxlength="80"
        />
        <button id="add-resource" class="btn" phx-disable-with="Cadastrando…">Cadastrar {@labels[
          "resource"
        ]}</button>
      </.form>
      <.operational_controls
        id="resource-browser"
        kind="resources"
        form={@resource_search_form}
        info={@read_pages.resources}
        label={"Buscar #{@labels["resources"]}"}
      />
      <div id="service-resources" phx-update="stream" class="operations-tables">
        <div :for={{id, resource} <- @streams.resources} id={id} class="operations-table">
          <strong>{resource.name}</strong>
          <.link
            :if={resource.session}
            id={"open-resource-#{resource.id}"}
            patch={session_path(@current_scope, @workflow_id, @pages, resource.session.id)}
            class="btn primary"
          >Atendimento #{resource.session.id} · {Instantflow.Operations.actor_name(resource.session)}</.link>
          <span :if={!resource.session}>Livre</span>
        </div>
      </div>
      <.form
        :if={@can_operate}
        for={@open_form}
        id="open-visit-form"
        phx-submit="open-visit"
        class="operations-form"
      >
        <.input
          field={@open_form[:resource_id]}
          type="select"
          label={"#{@labels["resource"]} disponível"}
          options={@resource_options}
          prompt="Selecione"
          required
        />
        <.input
          field={@open_form[:responsible_actor]}
          label={@labels["actor"]}
          required
          maxlength="120"
        />
        <.input field={@open_form[:business_date]} type="date" label="Dia operacional" required />
        <button id="open-visit" class="btn primary" phx-disable-with="Abrindo…">Abrir atendimento</button>
      </.form>
    </section>
    """
  end

  def items_block(assigns) do
    ~H"""
    <section class="card template-section">
      <div :if={@visit.session.status == "open"}>
        <.operational_controls
          id="catalog-items"
          kind="products"
          form={@product_search_form}
          info={@read_pages.products}
          label={"Buscar em todo o catálogo: #{@labels["catalog"]}"}
        />
        <p>
          Use a busca do catálogo para encontrar um produto; selecione nos resultados desta página.
        </p>
        <.form for={@item_form} id="add-item-form" phx-submit="add-item" class="operations-form">
          <div
            id="product-picker"
            phx-hook="ProductPicker"
            phx-update="ignore"
            data-source="product-picker-source"
            class="product-picker"
          >
            <.input
              id="product-query"
              name="item[query]"
              value=""
              label={"Buscar em #{@labels["catalog"]}"}
              autocomplete="off"
              role="combobox"
              aria-autocomplete="list"
              aria-expanded="false"
              aria-controls="product-suggestions"
            />
            <.input field={@item_form[:product_id]} type="hidden" label="" />
            <.input field={@item_form[:product_revision]} type="hidden" label="" />
            <ul id="product-suggestions" role="listbox" aria-label="Produtos encontrados" hidden></ul>
            <p id="product-selection-status" aria-live="polite">
              Digite para buscar; Enter seleciona a primeira opção.
            </p>
          </div>
          <.input
            field={@item_form[:quantity]}
            type="number"
            label="Quantidade"
            min="1"
            max="999"
            required
          />
          <.input field={@item_form[:notes]} label="Observações de preparo" maxlength="300" />
          <button id="add-item" class="btn" phx-disable-with="Adicionando…">Adicionar ao lote</button>
        </.form>
        <div id="product-picker-source" phx-update="stream" hidden>
          <span
            :for={{id, product} <- @streams.picker_products}
            id={id}
            data-product-id={product.id}
            data-revision={product.revision}
            data-name={product.name}
            data-category={product.category}
            data-price={product.price}
            data-destination={product.destination}
          >{product.name}</span>
        </div>
        <details id="quick-menu-shortcuts">
          <summary>Atalhos do catálogo</summary>
          <div id="quick-menu" phx-update="stream" class="operations-tables">
            <button
              :for={{id, product} <- @streams.quick_products}
              id={id}
              class="btn operations-quick-product"
              phx-click="quick-add"
              phx-value-id={product.id}
            >
              <strong>{product.name}</strong><span>{money(product.price)} · {product.destination}</span><span>+ 1 unidade</span>
            </button>
          </div>
        </details>
        <h3>Itens ainda não enviados</h3>
        <p>
          Este lote permanece apenas nesta tela até ser registrado. Registre antes de trocar de atendimento ou sair.
        </p>
        <div id="cart-items" phx-update="stream">
          <div :for={{id, item} <- @streams.cart_items} id={id} class="operations-product">
            <strong>{item.quantity} × {item.name}</strong><span>{item.destination} · {money(
              item.quantity * item.unit_price
            )} · {item.notes}</span>
            <button
              id={"remove-#{item.id}"}
              class="btn"
              phx-click="remove-item"
              phx-value-id={item.id}
            >Remover</button>
          </div>
        </div>
        <p id="cart-total">
          Lote: {money(
            Enum.reduce(@cart, 0, fn {_, i}, total -> total + i.quantity * i.unit_price end)
          )} · Ainda não incluído na conta
        </p>
        <.form
          for={@batch_form}
          id="submit-batch-form"
          phx-submit="submit-batch"
          class="operations-form"
        >
          <.input
            field={@batch_form[:responsible_actor]}
            label={"#{@labels["actor"]} deste lote"}
            required
            maxlength="120"
          />
          <button
            id="submit-batch"
            class="btn primary"
            disabled={map_size(@cart) == 0}
            phx-disable-with="Registrando…"
          >Registrar e separar por destino</button>
        </.form>
        <p>
          Registrar gera os tickets. Imprima cada destino e confirme a entrega manual. O diálogo de impressão não comprova impressão física.
        </p>
      </div>
    </section>
    """
  end

  def batches_block(assigns) do
    ~H"""
    <section class="card template-section">
      <.operational_pager id="batch-browser" kind="batches" info={@read_pages.batches} />
      <div id="fulfillment-batches" phx-update="stream">
        <article :for={{id, batch} <- @streams.batches} id={id} class="operations-batch">
          <h3>
            {batch.destination} · Ticket #{batch.id} {if batch.kind == "cancellation",
              do: "— CANCELAMENTO"}
          </h3>
          <p>
            {status(batch.status)} · {@labels["actor"]}: {Instantflow.Operations.actor_name(batch)} · {Instantflow.LocalTime.format(
              batch.inserted_at,
              @timezone
            )}
          </p>
          <p :if={batch.source_id}>Cancela o ticket #{batch.source_id}: {batch.reason}</p>
          <ul>
            <li :for={line <- batch.lines}>
              {line.quantity} × {line.name} · {money(line.quantity * line.unit_price)}
              <span :if={line.notes != ""}>— {line.notes}</span>
            </li>
          </ul>
          <button
            :if={batch.status != "cancelled" && @can_operate}
            id={"print-batch-#{batch.id}"}
            class="btn"
            phx-click="print-ticket"
            phx-value-id={batch.id}
          >{if batch.print_count > 0, do: "Reimprimir ticket", else: "Imprimir ticket"}</button>
          <button
            :if={batch.status == "pending" && @visit.session.status == "open" && @can_operate}
            id={"handoff-#{batch.id}"}
            class="btn"
            phx-click="handoff"
            phx-value-id={batch.id}
            data-confirm="Confirma que este papel foi entregue ao destino correto?"
          >Confirmar entrega manual</button>
          <.form
            :if={
              batch.kind == "order" && batch.status != "cancelled" &&
                @visit.session.status == "open" && @can_operate
            }
            for={to_form(%{}, as: :cancel)}
            id={"cancel-form-#{batch.id}"}
            phx-submit="cancel-batch"
            class="operations-form"
          >
            <.input
              type="hidden"
              name="cancel[batch_id]"
              value={batch.id}
              label=""
              id={"cancel-batch-id-#{batch.id}"}
            />
            <.input
              id={"cancel-reason-#{batch.id}"}
              name="cancel[reason]"
              value=""
              label="Motivo do cancelamento do lote inteiro"
              required
              maxlength="500"
            />
            <button
              id={"cancel-#{batch.id}"}
              class="btn"
              phx-disable-with="Cancelando…"
              data-confirm="Cancelar todos os itens deste ticket? Será gerado um aviso para o destino."
            >Cancelar lote</button>
          </.form>
        </article>
      </div>
    </section>
    """
  end

  def settlement_block(assigns) do
    ~H"""
    <section class="card template-section">
      <h3 id="visit-total">Total da conta: {money(@visit.total)}</h3>
      <.form
        :if={@visit.session.status == "open" && @can_operate}
        for={@checkout_form}
        id="checkout-form"
        phx-submit="settle"
        class="operations-form"
      >
        <.input
          field={@checkout_form[:payment_method]}
          type="select"
          label="Forma de pagamento recebida"
          options={@payment_options}
          prompt="Selecione após receber"
          required
        />
        <button
          id="settle-visit"
          class="btn primary"
          phx-disable-with="Fechando…"
          data-confirm="Confirma o recebimento e o fechamento desta conta?"
        >Registrar recebimento e liberar recurso</button>
      </.form>
      <p>
        Registro manual de recebimento. Sem integração bancária, emissão fiscal, descontos ou divisão de pagamentos nesta versão.
      </p>
    </section>
    """
  end

  def daily_summary_block(assigns) do
    ~H"""
    <section id="daily-report" class="card template-section">
      <h2>Resumo e fechamento diário</h2>
      <.form for={@day_form} id="day-form" phx-submit="day" class="operations-form">
        <.input field={@day_form[:date]} type="date" label="Dia operacional" required /><button
          id="load-day"
          class="btn"
        >Consultar</button>
      </.form>
      <p>
        O dia é escolhido ao abrir o atendimento; pode continuar após a meia-noite. Vendas e recebimentos são atribuídos a esse dia operacional.
      </p>
      <p id="day-sales">
        Contas encerradas: {@report.settled_count} · Vendas: {money(@report.sales)}
      </p>
      <p id="day-payments">
        Dinheiro: {money(@report.payments["cash"])} · Cartão: {money(@report.payments["card"])} · Pix: {money(
          @report.payments["pix"]
        )}
      </p>
      <p id="day-cancellations">Valor dos pedidos cancelados: {money(@report.cancellations)}</p>
      <p id="day-open">
        Contas abertas: {@report.open_count} · Saldo: {money(@report.open_total)}
      </p>
      <p :if={@report.archived_count > 0} id="day-archived">
        Atendimentos arquivados sem quitação: {@report.archived_count} · Valor histórico: {money(
          @report.archived_total
        )}. Não compõem vendas ou recebimentos; não ocupam recursos nem impedem o fechamento.
      </p>
      <p :if={@report.closed} id="day-closed">
        Dia encerrado em {Instantflow.LocalTime.format(@report.closed.inserted_at, @timezone)}. Novos atendimentos devem usar um dia posterior.
      </p>
      <button
        :if={!@report.closed && @can_operate}
        id="close-day"
        class="btn"
        phx-click="close-day"
        data-confirm="Encerrar este dia e impedir novos lançamentos nesta data ou em datas anteriores?"
      >Encerrar dia operacional</button>
      <h3>Consumo estimado de produtos</h3><p>
        Quantidades pedidas, incluindo o histórico arquivado e excluindo cancelamentos. Não confirma entrega nem representa saldo de estoque, ingredientes ou perdas de preparo.
      </p>
      <.operational_pager id="consumption-browser" kind="consumption" info={@read_pages.consumption} />
      <div id="estimated-consumption" phx-update="stream">
        <p :for={{id, row} <- @streams.consumption} id={id}>
          {row.name}: {row.quantity} unidade(s)
        </p>
      </div>
    </section>
    """
  end

  def print_block(assigns) do
    ~H"""
    <section
      :if={@print_ticket && @visit}
      id="operation-print"
      aria-label="Ticket para impressão"
    >
      <h1>{@print_ticket.destination}</h1>
      <strong :if={@print_ticket.kind == "cancellation"}>CANCELAMENTO DO TICKET #{@print_ticket.source_id}</strong>
      <strong :if={@print_ticket.copy > 1}>REIMPRESSÃO · Cópia {@print_ticket.copy}</strong>
      <p>
        {@visit.session.resource_name} · Atendimento #{@visit.session.id}<br />{@labels["actor"]}: {Instantflow.Operations.actor_name(
          @print_ticket
        )}<br />{Instantflow.LocalTime.format(
          @print_ticket.inserted_at,
          @timezone
        )}<br />Ticket #{@print_ticket.id}
      </p>
      <p :if={@print_ticket.reason}>{@print_ticket.reason}</p>
      <div :for={line <- @print_ticket.lines} class="print-line">
        <strong>{line.quantity} × {line.name}</strong><p :if={line.notes != ""}>{line.notes}</p>
      </div>
      <p>Conferir destino e entregar manualmente.</p>
    </section>
    """
  end

  defp cell(row, key) do
    case Enum.find(row.cells, &(&1.key == key)) do
      nil -> "—"
      %{value: nil} -> "—"
      %{value: value} when is_list(value) -> Enum.join(value, ", ")
      %{value: true} -> "Sim"
      %{value: false} -> "Não"
      %{value: value} -> to_string(value)
    end
  end

  defp money(cents), do: Operations.money(cents)
  defp status("pending"), do: "Aguardando entrega manual"
  defp status("handed"), do: "Entrega confirmada pelo operador"
  defp status("cancelled"), do: "Cancelado"
  defp status("archived"), do: "Arquivado sem confirmação de entrega"
end
