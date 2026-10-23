defmodule InstantflowWeb.AuthoringPanels do
  @moduledoc "Pure authoring projections; TemplateLive owns draft, revision and command state."
  use InstantflowWeb, :html
  alias Instantflow.WorkflowCatalog.{Interface, ParticipantPages}

  attr :budget_binding_options, :any, required: true
  attr :close_options, :any, required: true
  attr :communication_options, :any, required: true
  attr :department_options, :any, required: true
  attr :draft, :any, required: true
  attr :field_options, :any, required: true
  attr :finance_account_form, :any, required: true
  attr :interface_blocks, :any, required: true
  attr :interface_page_form, :any, required: true
  attr :interface_pages, :any, required: true
  attr :participant_audience_options, :any, required: true
  attr :role_options, :any, required: true
  attr :transition_options, :any, required: true
  attr :workspace_form, :any, required: true

  def workspace_panel(assigns) do
    ~H"""
    <section
      class="card template-section"
      id="workspace-configuration"
    >
      <h2>Interface gerada pelo processo</h2>
      <p>
        Defina páginas e componha seus blocos. Publicar gera os endereços dentro deste processo, sem criar telas no código.
      </p>
      <div class="process-page-tabs">
        <button
          :for={page <- @interface_pages}
          id={"edit-interface-#{page["key"]}"}
          class="btn"
          phx-click="pick-page"
          phx-value-key={page["key"]}
        >{page["label"]}</button><button id="new-interface-page" class="btn" phx-click="new-page">Nova página</button>
      </div>
      <.form for={@interface_page_form} id="interface-page-form" phx-submit="save-interface-page">
        <.input
          field={@interface_page_form[:key]}
          label="Chave da página"
          required
          pattern="[a-z][a-z0-9_]{0,63}"
          maxlength="64"
        />
        <.input
          field={@interface_page_form[:label]}
          label="Nome da página"
          required
          maxlength="80"
        />
        <.input
          field={@interface_page_form[:blocks]}
          type="select"
          multiple
          label="Blocos da página"
          options={
            Enum.map(
              @interface_blocks,
              &{Interface.block_label(&1), &1}
            )
          }
        />
        <.input
          field={@interface_page_form[:close_transition]}
          type="select"
          label="Transição usada no fechamento de atendimentos"
          options={@close_options}
          prompt="Não se aplica"
        />
        <fieldset
          :if={"operations" in @draft.definition["capabilities"]}
          id="operational-contract"
        >
          <legend>Contrato operacional v1</legend>
          <p>
            Responsável por nome registrado; recebimento manual integral em BRL; fuso da organização; consumo estimado de unidades.
          </p>
          <.input
            field={@interface_page_form[:payment_methods]}
            type="select"
            multiple
            label="Formas de pagamento aceitas"
            options={[{"Dinheiro", "cash"}, {"Cartão", "card"}, {"Pix", "pix"}]}
          />
        </fieldset>
        <.input
          :for={
            {key, label} <- [
              {"view", "Papéis que consultam os blocos"},
              {"configure", "Papéis que configuram catálogo e recursos"},
              {"operate", "Papéis que operam atendimentos e fechamento"}
            ]
          }
          name={"interface_page[access_#{key}][]"}
          id={"interface-access-#{key}"}
          type="select"
          multiple
          label={label}
          options={@role_options}
          value={@interface_page_form.params["access_" <> key] || []}
        />
        <fieldset id="participant-page-authoring">
          <.input
            field={@interface_page_form[:participant_messages]}
            type="select"
            multiple
            label="Mensagens selecionadas"
            options={@communication_options}
          />
          <legend>Projeção para participantes</legend>
          <.input
            field={@interface_page_form[:participant_enabled]}
            type="checkbox"
            label="Página de participação declarada"
          />
          <.input
            field={@interface_page_form[:participant_visibility]}
            type="select"
            multiple
            label="Papéis que veem a página"
            options={@role_options}
          />
          <.input
            field={@interface_page_form[:participant_audience]}
            type="select"
            multiple
            label="Audiência da projeção (exige acesso ao registro)"
            options={@participant_audience_options}
          />
          <.input
            field={@interface_page_form[:participant_fields]}
            type="select"
            multiple
            label="Campos liberados"
            options={@field_options}
          />
          <.input
            field={@interface_page_form[:participant_documents]}
            type="select"
            multiple
            label="Documentos liberados"
            options={@field_options}
          />
          <.input
            field={@interface_page_form[:participant_actions]}
            type="select"
            multiple
            label="Ações solicitadas"
            options={@transition_options}
          />
          <.input
            field={@interface_page_form[:participant_status]}
            type="checkbox"
            label="Mostrar situação atual"
          />
          <.input
            field={@interface_page_form[:participant_history]}
            type="checkbox"
            label="Mostrar histórico das ações selecionadas"
          />
        </fieldset>
        <fieldset id="finance-page-authoring">
          <legend>Capacidade financeira</legend>
          <.input
            field={@interface_page_form[:finance_binding]}
            type="select"
            label="Vínculo orçamentário"
            options={@budget_binding_options}
            prompt="Não configurado"
          />
          <.input
            field={@interface_page_form[:finance_scope]}
            type="select"
            label="Escopo do resumo"
            options={[
              {"Registros autorizados do processo", "process"},
              {"Conta compartilhada (exige autorização financeira)", "shared_account"}
            ]}
          />
          <.input
            field={@interface_page_form[:finance_roles]}
            type="select"
            multiple
            label="Papéis da projeção financeira"
            options={@role_options}
          />
        </fieldset>
        <button id="save-interface-page" class="btn" disabled={@draft.published_version_id != nil}>Salvar página</button>
      </.form>
      <ol id="interface-block-order">
        <li :for={{block, index} <- Enum.with_index(@interface_page_form.params["blocks"] || [])}>
          {Interface.block_label(block)}<button
            id={"move-block-up-#{index}"}
            class="btn"
            phx-click="move-interface-block"
            phx-value-index={index}
            phx-value-direction="up"
            disabled={@draft.published_version_id != nil}
          >Subir</button><button
            id={"move-block-down-#{index}"}
            class="btn"
            phx-click="move-interface-block"
            phx-value-index={index}
            phx-value-direction="down"
            disabled={@draft.published_version_id != nil}
          >Descer</button>
        </li>
      </ol>
      <.form
        for={@finance_account_form}
        id="template-finance-account"
        phx-submit="create-finance-account"
      >
        <.input
          field={@finance_account_form[:name]}
          label="Nova conta local (administração)"
          required
        />
        <.input
          field={@finance_account_form[:department_id]}
          type="select"
          label="Departamento da conta"
          options={@department_options}
          required
        />
        <button id="template-create-finance-account" class="btn">Criar conta local</button>
      </.form>
      <.form
        for={@workspace_form}
        id="workspace-labels-form"
        phx-submit="workspace-labels"
        class="operations-form"
      >
        <.input
          field={@workspace_form[:resource]}
          label="Recurso (singular)"
          maxlength="80"
          required
        />
        <.input
          field={@workspace_form[:resources]}
          label="Recursos (plural)"
          maxlength="80"
          required
        />
        <.input
          field={@workspace_form[:catalog]}
          label="Catálogo de itens"
          maxlength="80"
          required
        />
        <.input
          field={@workspace_form[:actor]}
          label="Responsável pelo atendimento"
          maxlength="80"
          required
        />
        <.input
          field={@workspace_form[:destination]}
          label="Destino do lote"
          maxlength="80"
          required
        />
        <button
          id="save-workspace-labels"
          class="btn"
          disabled={@draft.published_version_id != nil}
        >Salvar nomes</button>
      </.form>
    </section>
    """
  end

  attr :draft, :any, required: true
  attr :preview, :any, required: true
  attr :preview_form, :any, required: true
  attr :role_options, :any, required: true
  attr :stage_options, :any, required: true

  def participant_preview_panel(assigns) do
    ~H"""
    <section id="participant-preview" class="card">
      <h2>Prévia sintética de participação</h2>
      <p>
        Dados fictícios sob a política compartilhada. Vínculos e atribuições reais não são consultados; ações não são executadas.
      </p>
      <.form for={@preview_form} id="participant-preview-form" phx-submit="preview-participant">
        <.input
          field={@preview_form[:page]}
          type="select"
          label="Página"
          options={
            Enum.map(
              ParticipantPages.pages(@draft.definition),
              &{&1["label"], &1["key"]}
            )
          }
        />
        <.input
          field={@preview_form[:role]}
          type="select"
          label="Papel simbólico"
          options={@role_options}
        />
        <.input
          field={@preview_form[:stage]}
          type="select"
          label="Etapa"
          options={@stage_options}
        />
        <.input
          field={@preview_form[:verified]}
          type="checkbox"
          label="Relacionamentos verificados fictícios"
        />
        <button id="run-participant-preview" class="btn">Gerar prévia</button>
      </.form>
      <div
        :if={@preview}
        id="participant-preview-result"
        data-authorized={to_string(@preview.allowed?)}
      >
        <p :if={not @preview.allowed?}>Sem acesso nesta configuração.</p>
        <p :for={field <- @preview.fields} id={"preview-field-#{field.id}"}>
          {field.label}: {field.value}
        </p>
        <p :for={document <- @preview.documents}>{document} · Arquivo fictício</p>
        <p :for={action <- @preview.actions}>{action} · Ação simulada</p>
        <p :if={@preview.status}>{@preview.status}</p>
        <p :for={message <- @preview.messages}>
          {message} · Somente entregas ao destinatário autorizado
        </p>
      </div>
    </section>
    """
  end
end
