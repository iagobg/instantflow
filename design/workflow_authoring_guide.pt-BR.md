# Guia de criação de modelos de fluxo

[Índice do projeto](index.md) · Contrato implementado: `format_version: "1.0"`.

Anexe o [esquema JSON](../priv/templates/workflow-1.0.schema.json), o [catálogo de recursos](../priv/templates/capabilities-1.0.json), o [exemplo simples](examples/simple_approval.json) e, quando necessário, o [exemplo com campos tipados](examples/typed_approval.json). A validação de estrutura usa o próprio esquema entregue. Referências, tipos das condições e caminhos também passam pela validação semântica no servidor.

Forneça este guia à IA junto com o esquema JSON, o catálogo de recursos da versão e um exemplo válido. A IA elabora um rascunho; a pessoa administradora revisa regras, permissões e caminhos antes de publicar.

## Informações necessárias

- Objetivo, solicitantes e responsáveis por cada decisão.
- Etapas e condições para avançar, corrigir, rejeitar, cancelar e concluir.
- Campos, tipos, obrigatoriedade por etapa e informações confidenciais.
- Quem visualiza/edita cada seção e o que usuários externos podem ver.
- Regras de aprovação própria, orçamento e alterações após aprovação.
- Visualizações e ações simuladas necessárias.

Use dados fictícios. Não envie informações de estudantes, documentos reais, credenciais ou dados internos desnecessários ao serviço de IA.

Cada modelo será instalado na organização selecionada pela pessoa administradora. Use somente papéis e referências simbólicas; não inclua IDs de organizações, usuários ou recursos reais. O mapeamento ocorre dentro da organização de destino. Compartilhar um modelo não compartilha solicitações, estudantes, permissões ou atualizações futuras.

## Regras para o modelo

1. Produza JSON declarativo na versão solicitada. Não invente propriedades, tipos, operadores ou ações.
2. Use chaves técnicas estáveis e textos exibidos em português brasileiro.
3. Declare papéis simbólicos para mapeamento local. Não crie usuários, permissões globais ou identificadores reais.
4. Cada transição deve ter origem, destino e atores autorizados; cada etapa precisa de um caminho válido até um encerramento.
5. Separe informações confidenciais em seções com acesso explícito. Ler não significa editar ou aprovar.
6. Use apenas recursos do catálogo. Não inclua código, SQL, URLs de execução, segredos ou instruções para o servidor.
7. Faça perguntas sobre regras ausentes antes de gerar o JSON final.
8. Há uma etapa ativa por solicitação nesta versão; aprovações paralelas não são suportadas.
9. Pagamentos, mensagens e criação de contas são simulados e precisam de rótulos explícitos.

## Prompt reutilizável

> Elabore um modelo declarativo de fluxo para o InstantFlow. Siga exclusivamente o esquema JSON e o catálogo de recursos anexados, na versão informada. Use o exemplo como referência estrutural. Primeiro identifique ambiguidades de negócio e faça perguntas objetivas. Após receber as respostas, gere um único objeto JSON válido, sem comentários ou código executável. Use PT-BR nos textos exibidos. Declare papéis simbólicos sem conceder acesso. Inclua os caminhos de correção e encerramento exigidos e separe seções confidenciais. Não invente integrações ou recursos ausentes do catálogo. Requisitos do processo: [descreva aqui].

## Revisão antes de publicar

Confira quem aprova, se existe um caminho que pula revisão obrigatória, quem lê cada seção, cancelamentos e mudanças em valores aprovados. Confira mapeamentos e execute cenários de sucesso, correção, rejeição e acesso negado com dados fictícios.

Importar cria somente um rascunho. Validação estrutural não comprova regras de negócio. Nenhuma importação executa ações, cria usuários ou concede permissões. Publicar exige revisão e uma ação explícita da pessoa administradora.

## Contrato 1.0

- Use `format_version: "1.0"`, `locale: "pt-BR"`, `capabilities: ["core"]` (ou `["core", "finance"]` quando usar efeitos financeiros) e uma `template_version` no formato `1.0.0`. A versão publicada é controlada pelo servidor e não é essa versão do autor.
- Inclua todos os campos obrigatórios do esquema, inclusive `description`, `views`, `bindings`, `creation` e `assignment`. Não inclua propriedades adicionais.
- Chaves seguem `[a-z][a-z0-9_]{0,63}`. Referências a campos usam `secao.campo`. Chaves de cada coleção são únicas; mantenha-as estáveis ao revisar versões.
- `role_requirements` descreve papéis simbólicos. `creation.roles` informa quais podem iniciar solicitações. O mapeamento local para perfis já existentes não concede acesso a pessoas por si só.
- `bindings` declara vínculos simbólicos dos tipos `department` e `budget`. `assignment.department_binding` aponta para um deles. O departamento e a conta orçamentária reais são escolhidos dentro da organização, fora do JSON; cada tipo usa seu grupo de mapeamento local.
- Cada seção declara `classification` (`internal` ou `restricted`), campos e regras de `access`. Cada regra combina papel, `scope`, `read` e `edit_stages`. Uma seção restrita continua exigindo regras explícitas; a classificação sozinha não concede nem nega acesso.
- Em cada seção, use no máximo uma regra por par papel/escopo; reúna as etapas de edição nessa regra. Em uma transição, não repita ações idênticas de mesmo tipo e comportamento.
- `requester` limita a regra ao próprio solicitante. `assigned_department` exige o perfil mapeado no departamento atribuído. Um perfil recebido em outra organização nunca vale aqui.
- `guardian` exige vínculo local ativo e verificado com a matrícula; nomes e e-mails não substituem a verificação. O portal externo usa projeção própria e não recebe histórico interno. `workflow_department` exige `department_binding` simbólico na regra, vinculado ao mesmo perfil/departamento local.
- Uma transição pode declarar `department_binding` para transferir a fila ao departamento local de destino na mesma transação.
- Deve haver exatamente uma etapa `initial` e ao menos uma `terminal`. Todas as etapas precisam ser alcançáveis e ter caminho até um encerramento. Etapas finais não permitem edição silenciosa; somente transições `reopening` saem delas.
- Toda transição declara `actors`, `required_fields`, `require_reason`, `kind` e `actions`, mesmo quando listas ficam vazias. Atores nunca podem ficar vazios. Correção, rejeição, cancelamento e reabertura exigem motivo. `resubmission` precisa de uma transição de correção no sentido inverso.
- Use `disallow_requester: true` para impedir atuação do próprio solicitante. `finance_sensitive: true` também impede aprovação financeira própria, mesmo com perfis acumulados. `history_visibility` aceita `participants` ou `actors`.

## Tipos, condições e efeitos

`short_text` aceita até 200 caracteres; `long_text`, até 10.000. `integer` usa números inteiros seguros, entre -9.007.199.254.740.991 e 9.007.199.254.740.991. `money` usa centavos inteiros não negativos, com `currency` de três letras maiúsculas, por exemplo `BRL`. Não use valores decimais para dinheiro.

`date` é uma data ISO (`2026-10-20`). `datetime` é um instante ISO com deslocamento (`2026-10-20T14:00:00-03:00` ou `2026-10-20T17:00:00Z`). `boolean` usa `true`/`false`, não texto. `single_choice` e `multiple_choice` exigem `options` únicas; o valor é uma opção ou uma lista de opções distintas. `options` só aparece nesses dois tipos e `currency` só aparece em dinheiro. `null` representa ausência; a obrigatoriedade é declarada por transição em `required_fields`.

Condições são árvores declarativas em `guard`. Use `present` com `field`; `eq`, `gt`, `gte`, `lt`, `lte` com `field` e `value`; `in` com uma lista de valores compatíveis; `all`/`any` com `args`. Comparações ordenadas só aceitam inteiros, dinheiro, datas ou instantes. Há no máximo 8 níveis de condições e 20 argumentos por grupo. `delivery_succeeded` exige `kind` igual a uma ação simulada registrada. Exemplos completos estão em `typed_approval.json`.

As ações atuais são `simulate_notification`, `simulate_provisioning` e `simulate_payment`. Cada uma usa `behavior` igual a `success`, `fail_once` ou `failure`. São entregas fictícias pela fila durável. Não inclua endpoints, credenciais, código, SQL ou Python. Recursos de Python estão planejados para uma extensão separada e ainda são rejeitados.

`directory_reference` permanece reservado: valores não nulos são rejeitados. `attachment` aceita somente a chave opaca de um arquivo privado enviado pelo contexto autorizado, vinculado à mesma organização, solicitação, seção e campo. Nunca inclua chaves reais de arquivos em modelos. `attachment_ready` verifica a liberação e a validade no servidor; arquivos obrigatórios em `required_fields` também precisam estar prontos. O portal de matrícula e as seções privadas com atribuição nominal oferecem envio e revisão manual de documentos fictícios. Pagamentos reais continuam fora do contrato.

## Atribuição nominal e orçamento

O escopo assigned_user exige assignment_key, a chave de uma seção com configuração assignment. Essa configuração declara managers (atores autorizados), role, department_binding e stages para atribuição. Uma atribuição operacional identifica uma pessoa ativa da própria organização com o perfil/departamento exigidos; não é exportada. Mudanças usam revisão esperada e motivo, são auditadas e revogam o acesso anterior. Revogar é possível após o encerramento; atribuir novas pessoas exige uma das etapas configuradas. O editor avançado configura a estrutura; os controles tipados preservam sua semântica. Nunca exporte IDs de pessoas ou conteúdo de acompanhamento.

Com a capacidade finance, uma transição pode declarar finance com operation (reserve, post, release, reverse ou complete) e account_binding apontando para um vínculo budget. Reserve/post exigem amount_field de tipo money/BRL; complete exige quantity_field e received_field inteiros. Os efeitos ocorrem na mesma transação da etapa, fora da fila de integrações. Reserva exige perfil financeiro local e proíbe autoaprovação; alocação e estorno exigem permissões separadas. Não confunda os efeitos auditados com pagamento ou crédito real. Veja os modelos de requisição/passeio e as operações financeiras para os limites da demonstração.

## Visualizações

Cada item de `views` tem `key`, `label`, `type` (`table`, `board`, `calendar` ou `assignments`) e `columns`. Colunas referenciam campos por chave ou as colunas especiais `stage` e `assigned_department`. A tela de solicitações oferece essas visualizações. O calendário é uma agenda ordenada por campo date legível, com rótulo da etapa; a atribuição mostra o departamento atual. Quadros apresentam contagens autorizadas do fluxo. Cada linha respeita a versão fixada na solicitação e projeta somente os campos que a pessoa pode ler; mapear uma coluna restrita nunca a torna pública.

## Importação e revisão no produto

1. Acesse **Modelos de fluxo** como administrador da organização desejada. Cole JSON ou envie um arquivo `.json` de até 1 MiB.
2. Para uma cópia independente, use uma chave nova. Para atualizar um processo existente, selecione explicitamente o destino; sua chave deve coincidir. Importação nunca escolhe destino apenas pelo nome.
3. Corrija erros de estrutura, referências ou caminhos. Chaves JSON duplicadas, propriedades desconhecidas e versões não suportadas são rejeitadas. Limites adicionais: profundidade JSON 20, 100 etapas, 500 transições e 300 campos no total.
4. Resolva os mapeamentos de papéis e departamentos na organização de destino. Importações sempre começam sem mapeamentos, inclusive ao atualizar um processo.
5. Revise a comparação com a versão de origem, os avisos de autoridade excessiva e a prévia de papéis. Essa prévia não consulta solicitações ou pessoas reais.
6. Publique explicitamente. Rascunhos incompletos podem ser salvos, mas não publicados. Edições concorrentes com revisão antiga entram em conflito; compare e recupere os valores antes de recarregar.
7. Exporte apenas depois de revisar o conteúdo. A exportação contém a definição e um resumo SHA-256 para conferência; não contém mapeamentos reais, concessões, solicitações ou anexos. Rascunhos são identificados no arquivo e na tela. Rótulos e regras ainda podem revelar práticas internas.

Novas solicitações usam a última versão publicada. Solicitações em andamento permanecem na versão original. Uma nova importação em outra organização cria uma instalação independente, sem sincronização de dados ou atualizações futuras.
