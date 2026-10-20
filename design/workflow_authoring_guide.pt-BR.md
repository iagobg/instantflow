# Guia de criação de modelos de fluxo

[Índice do projeto](index.md) · Estado: proposta de contrato; importador ainda não implementado.

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

Importar cria somente um rascunho. Validação estrutural não comprova regras de negócio. O exemplo atual é ilustrativo; o esquema completo e catálogo serão entregues com o importador no Sprint 03.
