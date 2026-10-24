# Escola Horizonte: preparação isolada da demonstração

O setup D01 instala 12 matrículas, oito compras, seis passeios e três ocorrências
inteiramente fictícias. Os requisitos D01–D04 passaram na
[aceitação final a partir de instalação limpa](demo-readiness-final-acceptance.md).
O ensaio inclui o processo independente construído pela interface, permissões,
fluxo publicado, quadro por etapas, teclado, rótulos longos e estabilidade de sessão.

A sessão atual está em [127.0.0.1:4002](http://127.0.0.1:4002), com
[seis famílias separadas](demo-family-isolation.md), duas matrículas por conta.
Essa instalação nova usa o cluster local 55434; a instalação aceita anteriormente
no cluster 55433 permanece preservada, com o servidor parado. A demo antiga em
4001 também foi parada. O processo independente do ensaio anterior permanece
naquele banco preservado; a instalação atual começa com os quatro exemplos escolares.
As credenciais locais foram fornecidas na conversa; não estão no Git.
O [roteiro PT-BR](demo-readiness-rehearsal.md) e o
[relatório do relógio](demo-clock-remediation.md) detalham operação e limites.
A aceitação é local, com dados fictícios e integrações simuladas.

## Preparar e iniciar

Use o runtime fixado em .tool-versions, dependências já instaladas e PostgreSQL 16
local, conforme o README. Exporte as credenciais locais do operador e do runtime
por variáveis de ambiente; não grave credenciais no Git. Em um cluster existente,
preserve a senha atual do papel instantflow_runtime.

Em um terminal Bash, na raiz do projeto:

~~~sh
export MIX_ENV=dev
export PGHOST=localhost
export PGPORT=55434
export INSTANTFLOW_DEMO_DATABASE=instantflow_demo
# Remova destinos de operador usados em outros trabalhos neste terminal.
unset OPERATOR_DATABASE_URL MIGRATION_DATABASE
# Digite uma senha fictícia de 12 a 128 caracteres; ela não será exibida.
read -r -s -p 'Senha local dos novos usuários fictícios: ' DEMO_PASSWORD
export DEMO_PASSWORD
mix instantflow.demo.setup --database instantflow_demo
PORT=4002 mix phx.server
~~~

Abra [a demo local](http://127.0.0.1:4002). A porta separada permite manter um
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

As 13 contas usam a senha digitada na primeira instalação. Senhas existentes são preservadas.

| Conta | Papel local e concessões explícitas | Demonstração |
|---|---|---|
| admin@escola.example | Administração; teacher/head em Coordenação, finance/finance_allocator em Financeiro, operations em Operações, admissions em Secretaria e it em TI | Vê compras, passeios e matrículas; cria processos e executa as etapas autorizadas de outros solicitantes |
| docente@escola.example | Colaboradora; teacher em Coordenação | Vê apenas sua requisição de cadernos; edita e envia a proposta, sem aprovar ou reservar |
| compras@escola.example | Colaborador; teacher em Coordenação | Solicitante de seis compras, dos passeios e dos relatos de ocorrência; sem aprovar ou reservar |
| secretaria@escola.example | Colaboradora; admissions em Secretaria | Cria matrículas, verifica a família, revisa documentos e solicita correções |
| ti@escola.example | Colaborador; it em TI | Vê apenas identidade mínima, acompanha a falha simulada e tenta novamente o provisionamento |
| familia@escola.example | Participante externo; vínculo familiar verificado nos estudantes 01 e 05 | Vê e edita dados familiares nas etapas permitidas; não vê avaliação interna, pagamento ou notas privadas |
| familia.santos@escola.example | Participante externo; estudantes 02 e 06 | Apenas suas duas matrículas |
| familia.costa@escola.example | Participante externo; estudantes 03 e 07 | Apenas suas duas matrículas |
| familia.lima@escola.example | Participante externo; estudantes 04 e 08 | Apenas suas duas matrículas |
| familia.rocha@escola.example | Participante externo; estudantes 09 e 10 | Apenas suas duas matrículas |
| familia.alves@escola.example | Participante externo; estudantes 11 e 12 | Apenas suas duas matrículas |
| direcao@escola.example | Colaboradora; dean em Direção | Aprova segurança dos passeios; vê triagem/resolução das ocorrências; atribui orientação e simula comunicação |
| orientacao@escola.example | Colaboradora; counselor em Orientação | Vê relato e notas privadas apenas nos dois casos atribuídos; não vê disciplina nem comunicação |

A administração não ignora a separação de funções: uma pessoa não pode reservar
orçamento ou confirmar pagamento para sua própria solicitação. O apresentador
não recebe dean, counselor ou finance_reverser e não descobre os três incidentes.
A direção também não lê as notas privadas da orientação. Todas as pessoas e
referências são fictícias; nenhum pagamento, envio ou provisionamento é real.

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
   a aceitação visual completa permanece em D04; o quadro D03 já está implementado.

## Matrículas, passeios e ocorrências (D01)

| Processo | Distribuição inicial da publicação primária |
|---|---|
| Matrículas (12) | Rascunho 2; documentos 2; correção 1; acadêmica 2; pagamento 2; provisionamento 2; concluída 1 |
| Passeios (6) | Proposta, acadêmica, financeira, transporte, segurança e aprovado: um em cada |
| Ocorrências (3) | Triagem 1; acompanhamento 1; encerrada 1 |

As matrículas têm nome fictício, série, família verificada e um PDF privado
inofensivo por caso. Sete documentos já foram revisados pela Secretaria;
os demais aguardam revisão. Dois provisionamentos estão com falha simulada
para demonstrar **Tentar novamente** com TI. O concluído registra falha, nova
tentativa e sucesso antes de concluir. A avaliação acadêmica é interna.
Os documentos expiram após 30 dias; não são renovados no rerun. Para um ensaio
posterior à validade, prepare outra instalação isolada. Bases com o vínculo antigo
compartilhado são recusadas pelo setup; ele não redistribui vínculos já editados.
Preserve a base antiga e use um cluster novo para a distribuição de seis famílias.

1. Como admin, abra Matrícula de estudantes, selecione Etapas da matrícula e
   Filtrar. Compare o quadro e o fluxo publicado; abra a matrícula concluída e
   confira o histórico simulado. A Secretaria criou os casos, permitindo a
   confirmação financeira pelo apresentador sem violar separação de funções.
2. Como família, abra a página Família do processo. Confira somente as duas matrículas da família Oliveira,
   escolha a que aguarda correção, ajuste a série e reenvie. Compare com a visão
   interna: avaliação, pagamento e identidade mínima de TI não são expostos.
3. Como admin, abra Aprovação de passeios: há destinos, datas, roteiro, riscos e
   transporte fictícios. O calendário usa as datas de novembro de 2026. A aprovação
   de segurança exige a conta Direção; o orçamento é o mesmo fundo sintético de compras.
4. O exemplo confidencial é opcional. Admin e docente veem zero ocorrências.
   Entre como Direção para triagem/resolução; depois Orientação para as notas dos
   dois casos atribuídos. Não copie notas privadas na comunicação curada.

O setup preserva casos editados, senhas, documentos, tentativas e versões antigas.
Uma publicação aposentada é substituída por uma nova primária sem reescrever pins.
A melhoria de cartões da matrícula admite somente a publicação anterior conhecida,
com bindings iguais: publica uma nova versão com nome/série no quadro. Outros
desvios falham explicitamente. No banco já usado em ensaios, os casos antigos ficam
na versão anterior; o inventário separa as contagens por publicação.

## Quadro por etapas (D03)

No processo, selecione **Gargalos por etapa** em Visualização e clique em **Filtrar**.
O quadro mostra a versão publicada selecionada, inclusive etapas vazias e os totais
autorizados por coluna. Cada coluna tem até dez cartões por página; processos com
mais de dez etapas também têm paginação de etapas. Use a rolagem horizontal ou o
teclado para chegar às etapas finais. Abra um cartão com Ctrl+clique para manter
o quadro conectado enquanto executa a ação normal no caso em outra aba.

O [relatório D03](stage-boards.md) registra o ensaio, capturas e limites. Nesse ensaio,
o caso #2 (Livros) avançou de Aprovação da área para Aprovação financeira. As outras
alterações de D02 foram preservadas. A falha intermitente de sessão foi reproduzida
em um teste completo e continua como pendência explícita de D04; o diagnóstico
capturou uma rejeição de token com timestamp 2907 ms à frente do relógio do
verificador. A estabilidade do relógio local não foi corrigida; esse resultado
não explica automaticamente ocorrências antigas sem rastreamento.

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

O [ensaio visual de D02](demo-flow-visual-rehearsal.md) foi executado em 1280 × 720.
Foram verificados navegação, seleção/rolagem por teclado, atualização em outra aba,
edição permitida, conta restrita e estado de acesso negado. Um ajuste no hook passou
a centralizar a etapa atual quando o diagrama do caso é aberto. O limite anterior
do serviço de aprovação do navegador não se repetiu.

O ensaio deixou o caso #3 em Compra e atualizou a justificativa do caso #7. Também
criou o rascunho #1, ainda não publicado, para testar rótulos longos. A versão
publicada continua sendo v1. O setup preservará essas mudanças; o inventário acima
continua descrevendo o cenário inicial de uma instalação limpa. O relatório registra
as contagens finais, capturas e os testes visuais ainda pendentes para D03/D04.

Validação D02: suite focada de fluxo/editor com 20 testes e zero falhas (seed
830214); mix assets.build passou; mix precommit passou com 360 testes e zero falhas
(seed 636776); git diff --check passou. A implementação parte do commit D01
29156a4. D01 ainda tem cenários pendentes. D03 foi implementado e ensaiado separadamente; D04 permanece incompleto.

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
