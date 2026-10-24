# Escola Horizonte: preparação isolada da demonstração

Este é o primeiro checkpoint de D01 do [plano de demo](../sprint_plan/demo_readiness.md).
Instala uma escola fictícia com oito requisições de compra. Matrículas, passeios,
ocorrências confidenciais e quadro por etapas continuam pendentes. O fluxo publicado
foi implementado no checkpoint D02, com aceitação visual ainda pendente.
A grade atual de cartões ainda não é o quadro D03.

## Preparar e iniciar

Use o runtime fixado em .tool-versions, dependências já instaladas e PostgreSQL 16
local, conforme o README. Exporte as credenciais locais do operador e do runtime
por variáveis de ambiente; não grave credenciais no Git. Em um cluster existente,
preserve a senha atual do papel instantflow_runtime.

Em um terminal Bash, na raiz do projeto:

~~~sh
export MIX_ENV=dev
export PGHOST=localhost
export PGPORT=55432
export INSTANTFLOW_DEMO_DATABASE=instantflow_demo
# Remova destinos de operador usados em outros trabalhos neste terminal.
unset OPERATOR_DATABASE_URL MIGRATION_DATABASE
# Digite uma senha fictícia de 12 a 128 caracteres; ela não será exibida.
read -r -s -p 'Senha local dos novos usuários fictícios: ' DEMO_PASSWORD
export DEMO_PASSWORD
mix instantflow.demo.setup --database instantflow_demo
PORT=4001 mix phx.server
~~~

Abra [a demo local](http://localhost:4001). A porta separada permite manter um
servidor de desenvolvimento existente. O seletor de banco deve permanecer exportado
no terminal do servidor: as duas conexões usam instantflow_demo. Sem a variável,
a configuração de desenvolvimento continua usando instantflow_dev.

Somente em um **cluster novo**, antes do primeiro setup, provisione o login do runtime:

~~~sh
mix ecto.create -r Instantflow.OperatorRepo
mix ecto.migrate -r Instantflow.OperatorRepo
mix instantflow.db_roles
~~~

Esses comandos exigem as mesmas variáveis da demo acima. O último configura a
senha do papel compartilhado do cluster; não o use para trocar inadvertidamente
uma senha usada por outros bancos. O setup normal não altera esse papel.

O setup exige ambiente dev, seleção explícita de instantflow_demo e ambas as
conexões no mesmo host/porta local. Recusa produção, banco omitido, outro nome,
URL de operador, socket alternativo ou divergência entre destinos. Não executa
os seeds antigos e não toca nos bancos de trabalho existentes.

## Contas e limites de acesso

As três contas novas usam a senha digitada. Senhas existentes são preservadas.

| Conta | Papel local e concessões explícitas | Demonstração |
|---|---|---|
| admin@escola.example | Administração; teacher/head em Coordenação, finance/finance_allocator em Financeiro, operations em Operações | Vê as oito compras, cria processos, aprova e executa compras de outro solicitante; edita sua proposta devolvida |
| docente@escola.example | Colaboradora; teacher em Coordenação | Vê apenas sua requisição de cadernos; edita e envia a proposta, sem aprovar ou reservar |
| compras@escola.example | Colaborador; teacher em Coordenação | Solicitante das outras seis compras; sem permissão de aprovar ou reservar |

A administração não ignora a separação de funções: uma pessoa não pode reservar
orçamento para sua própria solicitação. Não concedemos dean, counselor ou
finance_reverser ao apresentador. Este checkpoint não cria ocorrências nem
contas de familiares; a demo confidencial será acrescentada separadamente com
pessoas explicitamente autorizadas.

## Inventário inicial e roteiro curto

O comando imprime JSON com banco, versão primária, todas as versões preservadas,
contagens por etapa e papéis disponíveis. A publicação inicial de requisição é v1.

| Etapa | Casos | Exemplo |
|---|---:|---|
| Solicitada | 2 | Cadernos; tecidos devolvidos para revisão |
| Aprovação da área | 1 | Livros |
| Aprovação financeira | 1 | Tintas |
| Compra | 1 | Jogos de lógica |
| Recebimento | 1 | Sementes; recebimento parcial de 2 unidades |
| Concluída | 1 | Mapas |
| Cancelada | 1 | Pastas |

A dotação fictícia é R$ 10.000,00. Os casos têm título, justificativa, quantidade,
valor e atribuição de departamento. Este modelo não possui campos de prazo ou
urgência; nenhum campo foi inventado fora do contrato publicado. Não há documentos
ou integrações externas neste processo. Pedidos e recebimentos são simulados.

1. Entre como admin e abra Processos → Requisição de materiais e bens → Acompanhamento.
2. Abra a compra de tintas e execute Reservar orçamento. Observe a etapa Compra.
3. Abra tecidos e confira no histórico a devolução da aprovação da área para Solicitada.
   Edite a justificativa e reenvie para análise.
4. Em outra sessão, entre como docente: só a compra de cadernos aparece. Envie-a;
   essa conta não recebe ações de aprovação/reserva e não descobre as outras compras.
5. Volte à sessão admin e confira a atualização. Isso é um roteiro preliminar;
   a aceitação visual completa e a atualização do futuro quadro pertencem a D03/D04.

## Fluxo publicado (D02)

1. No processo, escolha **Ver fluxo publicado**. O cabeçalho identifica o número,
   a publicação e o contexto da versão mais recente. A visão geral acompanha novas
   publicações, preservando o filtro de destaque escolhido.
2. Escolha uma etapa em **Destacar conexões da etapa** para acompanhar suas entradas
   e saídas. O diagrama tem rolagem própria; **Lista de etapas e conexões** mantém
   os nomes completos, os destinos e as indicações inicial/final em texto.
3. Abra um caso e escolha **Ver fluxo desta versão**. A versão é a fixada no caso,
   inclusive quando existe publicação mais nova ou rascunho alterado. A etapa atual
   aparece no diagrama e na lista. Transições e correções por outro usuário atualizam
   essa indicação através das invalidações já usadas pelo runtime.
4. Use **Voltar ao registro** ou **Voltar aos casos**. Administradores também têm
   um link para **Modelos de fluxo**; colaboradores podem consultar o fluxo sem
   receber acesso à edição.

As rotas são /o/horizonte/processos/ID/fluxo e
/o/horizonte/processos/ID/registros/CASO/fluxo. A consulta não aceita um ID de versão
arbitrário: a visão geral resolve a publicação atual e o caso resolve seu próprio pin.
A tela informa quando uma versão é histórica/arquivada.

O diagrama só recebe nomes, chaves, tipos de conexão e marcas inicial/final. Não
recebe vínculos locais, valores dos formulários, configuração de efeitos ou guardas.
Conexões cujo histórico é restrito aos atores ficam fora da visão geral; no caso,
a política existente de histórico determina quais aparecem. As ações permitidas
continuam sendo verificadas na experiência normal do registro. Públicos de páginas
de participantes não ganham uma rota alternativa para um diagrama interno. Acesso
revogado limpa o diagrama aberto após a invalidação/revalidação.

O ensaio visual deste checkpoint está pendente: a abertura automatizada de
localhost:4001 foi bloqueada porque o serviço de revisão automática de aprovação
atingiu seu limite de uso. Isso não foi uma rejeição manual do usuário. Não houve
captura de navegador nem confirmação visual de tamanho, rolagem ou foco por teclado.
Os testes de LiveView comprovam os elementos e as atualizações de estado, mas não
substituem essa inspeção.

Validação D02: suite focada de fluxo/editor com 20 testes e zero falhas (seed
830214); mix assets.build passou; mix precommit passou com 360 testes e zero falhas
(seed 636776); git diff --check passou. A implementação parte do commit D01
29156a4. D01 ainda tem cenários pendentes; D03 e D04 ainda não foram implementados.

## Repetir, preservar ou reiniciar

Execute o mesmo setup novamente para completar casos ainda não criados. Cada
caso e seu histórico inicial são uma única transação com chave fixa por versão.
Se um passo falhar, a transação inteira desse caso falha explicitamente. Casos
já criados não são editados ou avançados novamente, mesmo após uso pelo apresentador.
A alocação do orçamento também possui chave idempotente. Grants previstos são
reestabelecidos pelo setup; contas revogadas/inativas não são reativadas.

Publicações ativas divergentes do fixture interrompem o setup para revisão.
Publicações aposentadas permanecem intactas: uma nova versão suportada e seus
casos tornam-se a história principal. O inventário distingue versões anteriores.

Para voltar ao cenário inicial, pare o servidor da demo e execute **somente se
quiser descartar todo o conteúdo de instantflow_demo**:

~~~sh
mix instantflow.demo.setup --reset --database instantflow_demo
~~~

O reset não aceita outro banco ou um destino implícito. Ele remove também edições,
novos processos e contas criadas na demo; os bancos dev/test ficam preservados.
Não use mix ecto.reset para este roteiro.

## Evidência do checkpoint

Em 2026-10-23: criação limpa de instantflow_demo, migrações e duas execuções do
setup passaram. Ambas reportaram oito casos, uma publicação e as mesmas sete
etapas. Foi usado o login de runtime já provisionado no cluster local; não houve
reset de banco existente nem alteração de senha do papel do cluster.

Validação final: mix precommit passou com 350 testes e zero falhas (seed 487092).
Os quatro testes novos passaram também isoladamente. O comando CLI recusou
--reset --database instantflow_dev antes de qualquer tarefa Ecto; git diff --check
passou. O servidor isolado na porta 4001 respondeu HTTP 200 na página de login.
O navegador foi encaminhado a essa URL para inspeção; não há evidência de ensaio
visual autenticado neste checkpoint.

Os testes em test/instantflow/demo cobrem destinos recusados, senhas inválidas,
contagens autorizadas, propostas preenchidas, avanço permitido/negado, retorno
para revisão, rerun após ação do apresentador, senha preservada, efeitos financeiros
sem replay e versões aposentadas preservadas. A verificação de interface completa
não foi executada neste checkpoint; contagens de testes não comprovam prontidão
visual da demo.
