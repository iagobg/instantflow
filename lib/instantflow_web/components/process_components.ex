defmodule InstantflowWeb.ProcessComponents do
  @moduledoc "Reusable process block templates. Contexts and LiveViews own queries, authorization and commands."
  use InstantflowWeb, :html
  import InstantflowWeb.ProcessRoutes
  import InstantflowWeb.PaginationControls
  alias Instantflow.Operations

  def finance_setup_block(assigns) do
    ~H"""
    <section id="process-finance-setup" class="card">
      <h2>Configuração financeira local</h2>
      <p :if={@finance_surface.setup_error} id="process-finance-setup-error" role="alert">
        {InstantflowWeb.RuntimeErrors.message(@finance_surface.setup_error)}
      </p>
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
      <p
        :if={not is_nil(@finance_surface.setup_error) and "finance_setup" not in @blocks}
        id="process-finance-summary-error"
        role="alert"
      >
        {InstantflowWeb.RuntimeErrors.message(@finance_surface.setup_error)}
      </p>
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

  def record_presentation_navigation(assigns) do
    ~H"""
    <div
      id="record-presentations"
      phx-update="stream"
      aria-label="Apresentação dos registros"
      class="process-view-options"
    >
      <button
        :for={{id, view} <- @streams.record_presentations}
        id={id}
        type="button"
        class={["btn", view.selected? && "primary"]}
        aria-pressed={to_string(view.selected?)}
        phx-click="record-presentation"
        phx-value-view={view.key}
      >
        {Map.fetch!(
          %{
            "table" => "Lista",
            "board" => "Quadro de Acompanhamento",
            "calendar" => "Calendário",
            "assignments" => "Atribuições"
          },
          view.type
        )}<span :if={view.disambiguate?}> · {view.view_label}</span>
      </button>
    </div>
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
      <p :if={!@records_loading? && @record_view_options == []} id="process-record-views-empty">
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
        <input type="hidden" name="record_filter[view]" value={@record_view} />
        <.input
          :if={@record_view_type == "board" && @stage_board.version_options != []}
          field={@record_form[:version_id]}
          type="select"
          label="Versão publicada do quadro"
          options={Enum.map(@stage_board.version_options, &{"Versão #{&1.number}", &1.id})}
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
      <.pagination
        id="record-view-browser"
        event="record-view-page"
        info={@record_views}
        label="visualização(ões)"
      />
      <p :if={@show_board_setup?} id="board-setup-guidance" class="small-text">
        <span :if={@record_views.pages > 1}>Consulte também as outras páginas de visualizações.</span>
        Para adicionar um quadro de acompanhamento, abra
        <.link navigate={~p"/o/#{@current_scope.organization.slug}/modelos"}>Modelos de fluxo</.link>
        e configure uma visualização do tipo Quadro.
      </p>
      <p id="process-record-preview-note" class="small-text">
        Textos longos mostram até 80 caracteres. Abra o registro para ver o conteúdo completo.
      </p>
      <p :if={@records_loading?} id="process-record-loading" role="status">
        Carregando registros autorizados…
      </p>
      <p :if={!@records_loading?} id="process-record-count">
        {@record_total} registro(s) disponível(is)
      </p>
      <p id="process-urgency-status" role="status" aria-live="polite">
        {@record_urgent} registro(s) com maior urgência em aberto.
      </p>
      <.stage_board :if={@record_view_type == "board" && !@records_loading?} {assigns} />
      <div
        :if={@record_view_type != "board"}
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
              InstantflowWeb.RecordNavigation.with_context(
                ~p"/o/#{@current_scope.organization.slug}/processos/#{@workflow_id}/registros/#{row.id}",
                @record_navigation
              )
            }
            class="btn"
          >Abrir registro</.link>
        </article>
      </div>
      <nav
        :if={@record_view_type != "board" && @record_pages > 1}
        id="process-record-pagination"
        aria-label="Páginas de registros"
      >
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

  def stage_board(assigns) do
    ~H"""
    <div id="process-stage-board">
      <p :if={!@stage_board.available?} id="board-unavailable" role="status">
        Esta versão do quadro está indisponível para seu perfil. Selecione uma versão autorizada.
      </p>
      <nav
        :if={@stage_board.version_pages > 1}
        id="board-version-pages"
        aria-label="Páginas de versões"
      >
        <button
          id="board-versions-previous"
          class="btn"
          phx-click="board-versions-page"
          phx-value-page={@stage_board.version_page - 1}
          disabled={@stage_board.version_page <= 1}
        >Versões anteriores nesta lista</button>
        <span>Página {@stage_board.version_page} de {@stage_board.version_pages} · {@stage_board.version_total} versões autorizadas</span>
        <button
          id="board-versions-next"
          class="btn"
          phx-click="board-versions-page"
          phx-value-page={@stage_board.version_page + 1}
          disabled={@stage_board.version_page >= @stage_board.version_pages}
        >Mais versões históricas</button>
      </nav>
      <div :if={@stage_board.version}>
        <h3 id="board-version" data-version-id={@stage_board.version.id}>
          Quadro · Versão {@stage_board.version.number}
          {if @stage_board.version.current?, do: "· Publicação atual", else: "· Publicação anterior"}
        </h3>
        <p :if={@stage_board.version.archived?} id="board-archived" role="status">
          Versão arquivada. Os casos estão preservados para consulta.
        </p>
        <p id="board-version-note">
          Este quadro contém apenas casos desta versão. Abra um caso para consultar seu fluxo e suas ações permitidas.
        </p>
        <p id="board-loaded-count" aria-live="polite">
          {@stage_board.loaded} exibidos de {@stage_board.total} casos correspondentes · até {@stage_board.card_limit} por etapa
        </p>
        <nav
          :if={@stage_board.columns_pages > 1}
          id="board-column-pages"
          aria-label="Páginas de etapas"
        >
          <button
            id="board-columns-previous"
            class="btn"
            phx-click="board-columns-page"
            phx-value-version_id={@stage_board.version.id}
            phx-value-page={@stage_board.columns_page - 1}
            disabled={@stage_board.columns_page <= 1}
          >Etapas anteriores</button>
          <span>Etapas · Página {@stage_board.columns_page} de {@stage_board.columns_pages} · {@stage_board.stage_total} etapas</span>
          <button
            id="board-columns-next"
            class="btn"
            phx-click="board-columns-page"
            phx-value-version_id={@stage_board.version.id}
            phx-value-page={@stage_board.columns_page + 1}
            disabled={@stage_board.columns_page >= @stage_board.columns_pages}
          >Próximas etapas</button>
        </nav>
        <div
          id="stage-board-scroll"
          class="stage-board-scroll"
          tabindex="0"
          role="region"
          aria-label="Quadro de casos com rolagem horizontal"
        >
          <div id="stage-board-columns" class="stage-board-columns">
            <section
              :for={column <- @board_columns}
              id={"board-column-#{column.id}"}
              class="stage-board-column"
              aria-labelledby={"board-heading-#{column.id}"}
            >
              <h4 id={"board-heading-#{column.id}"}>{column.label}</h4>
              <p :if={column.initial? || column.terminal?} class="small-text">
                {if column.initial?, do: "Inicial "}{if column.terminal?, do: "Final"}
              </p>
              <p id={"board-count-#{column.id}"} class="small-text" aria-live="polite">
                {column.loaded} exibidos de {column.total} correspondentes
              </p>
              <p :if={column.total == 0} id={"board-empty-#{column.id}"}>
                Nenhum caso correspondente nesta etapa.
              </p>
              <div id={"board-cards-#{column.id}"} phx-update="stream">
                <article :for={{id, row} <- @streams[column.stream]} id={id} class="stage-board-card">
                  <h5>#{row.id} · {InstantflowWeb.ProjectionDisplay.preview(row.title)}</h5>
                  <p class="badge">{row.stage_label}</p>
                  <p :if={row.assignment}>Responsável: {row.assignment}</p>
                  <p :if={row.urgency}>Urgência: {row.urgency}</p>
                  <dl>
                    <div :for={cell <- row.cells}>
                      <dt>{cell.label}</dt><dd>
                        {InstantflowWeb.ProjectionDisplay.preview(cell.value)}
                      </dd>
                    </div>
                  </dl>
                  <.link
                    id={"open-process-record-#{row.id}"}
                    class="btn"
                    navigate={
                      InstantflowWeb.RecordNavigation.with_context(
                        ~p"/o/#{@current_scope.organization.slug}/processos/#{@workflow_id}/registros/#{row.id}",
                        @record_navigation
                      )
                    }
                  >Abrir registro</.link>
                </article>
              </div>
              <nav
                :if={column.pages > 1}
                id={"board-pagination-#{column.id}"}
                aria-label={"Casos em #{column.label}"}
              >
                <button
                  id={"board-previous-#{column.id}"}
                  class="btn"
                  phx-click="board-card-page"
                  phx-value-stage={column.id}
                  phx-value-version_id={@stage_board.version.id}
                  phx-value-page={column.page - 1}
                  disabled={column.page <= 1}
                >Anterior</button>
                <span>{column.page} / {column.pages}</span>
                <button
                  id={"board-next-#{column.id}"}
                  class="btn"
                  phx-click="board-card-page"
                  phx-value-stage={column.id}
                  phx-value-version_id={@stage_board.version.id}
                  phx-value-page={column.page + 1}
                  disabled={column.page >= column.pages}
                >Próxima</button>
              </nav>
            </section>
          </div>
        </div>
      </div>
    </div>
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
    <.pagination event="operational-page" id={@id} kind={@kind} info={@info} />
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
      <.pagination
        event="operational-page"
        id="batch-browser"
        kind="batches"
        info={@read_pages.batches}
      />
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
      <.pagination
        event="operational-page"
        id="consumption-browser"
        kind="consumption"
        info={@read_pages.consumption}
      />
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
    value =
      case Enum.find(row.cells, &(&1.key == key)) do
        nil -> nil
        cell -> cell.value
      end

    InstantflowWeb.ProjectionDisplay.preview(value)
  end

  defp money(cents), do: Operations.money(cents)
  defp status("pending"), do: "Aguardando entrega manual"
  defp status("handed"), do: "Entrega confirmada pelo operador"
  defp status("cancelled"), do: "Cancelado"
  defp status("archived"), do: "Arquivado sem confirmação de entrega"
end
