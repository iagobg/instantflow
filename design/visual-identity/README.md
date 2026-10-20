# Identidade Visual — InstantFlow

[Design index](../index.md)

Guia de identidade visual, tokens de design, logotipos e página de exemplo para capturas de tela.

## Princípios visuais

1. **Clareza antes de decoração**: densidade de ferramenta de trabalho escolar; o roxo (`Violeta Fluxo`) marca ação primária, etapa ativa e foco de teclado.
2. **Temas claro e escuro com contraste verificado**:
   - **Modo claro**: fundo branco (`#FFFFFF`), superfícies sutis (`#FAFAFC` / `#F5F5F8`) e acento principal `Violeta 700` (`#6128CC`, contraste `7,82:1` com branco).
   - **Modo escuro**: fundo cinza-grafite (`#1B1B1F`), cartões elevados (`#232328` / `#2B2B31`), botão primário `Violeta 600` (`#7438E4`) e texto/ícones de acento `#B394FF` (contraste `7,03:1` no fundo da página e `6,40:1` sobre cartões).
3. **Estado nunca só por cor**: todo selo de status combina ícone + rótulo em PT-BR e funciona em escala de cinza.
4. **Simulação e sigilo explícitos**:
   - Capacidades simuladas (pagamento, notificação, criação de acesso) usam o marcador tracejado verde-azulado (`--if-sim`, `#0E7068` / `#4FD1C1`).
   - Seções restritas (notas da orientação educacional) usam o marcador ameixa (`--if-restricted`, `#8A2C6B` / `#EE8FCB`) com ícone de cadeado.
5. **Tempo real com calma**: presença (`Ana está editando`) é discreta e consultiva; atualizações concorrentes exibem aviso claro (`Esta solicitação foi atualizada`) preservando rascunhos sem sobrescrever nem reordenar silenciosamente o item ativo.

## Estrutura de arquivos

| Arquivo | Finalidade |
|---|---|
| [`tokens.css`](tokens.css) | Fonte única de verdade em CSS custom properties (`--if-*`) para cores, tipografia, espaçamento, raios, sombras e movimento nos temas claro e escuro |
| [`tailwind-theme.css`](tailwind-theme.css) | Mapeamento proposto para Tailwind v4 / daisyUI 5 (Phoenix 1.8) |
| [`components.css`](components.css) | Estilos de referência para botões, selos, alertas, campos, tabela, Kanban, medidor de orçamento e gaveta de detalhes |
| [`brand-sheet.html`](brand-sheet.html) | Prancha completa da identidade visual (logotipo, paleta, tipografia, componentes e voz em PT-BR) |
| [`examples/painel-passeios.html`](examples/painel-passeios.html) | Página de exemplo não funcional (*Aprovação de passeios*) pronta para capturas de tela (`?theme=light`, `?theme=dark`, `?drawer=closed`) |
| [`logo/`](logo/) | Logotipo principal, versão empilhada e símbolos da marca em SVG (textos convertidos em curvas para independência de fonte) |
| [`screenshots/`](screenshots/) | Capturas PNG renderizadas em modo claro e escuro |

## Logotipo e símbolos (`logo/`)

Na assinatura **InstantFlow**, a haste vertical do **`i`** desce sob `nstant`, sobe em curva entre as duas palavras e atravessa o centro geométrico de `flow` como uma seta contínua (com recorte em máscara transparente, adaptando-se a qualquer superfície). O ícone quadrado (`mark`) e o glifo sintetizam esse mesmo movimento em curva em “S” do `i` em direção à seta:

- [`instantflow-logo-light.svg`](logo/instantflow-logo-light.svg) — assinatura horizontal para modo claro (`instant` em `#1C1B22`, `flow` e seta em `#6128CC`)
- [`instantflow-logo-dark.svg`](logo/instantflow-logo-dark.svg) — assinatura horizontal para modo escuro (`instant` em `#EDEDF2`, `flow` e seta em `#A37CFA`)
- [`instantflow-logo-on-accent.svg`](logo/instantflow-logo-on-accent.svg) — assinatura horizontal para aplicação sobre fundos violeta (`instant` em `#FFFFFF`, `flow` e seta em `#D9C9FF`)
- [`instantflow-logo-stacked-light.svg`](logo/instantflow-logo-stacked-light.svg) · [`instantflow-logo-stacked-dark.svg`](logo/instantflow-logo-stacked-dark.svg) — assinatura vertical empilhada (ícone + logotipo) para telas de entrada e apresentação
- [`instantflow-mark.svg`](logo/instantflow-mark.svg) — ícone quadrado principal em gradiente violeta (`#8A57F2 → #5021A6`)
- [`instantflow-mark-mono.svg`](logo/instantflow-mark-mono.svg) — ícone monocromático vazado (`currentColor`)
- [`instantflow-glyph-white.svg`](logo/instantflow-glyph-white.svg) — glifo branco isolado para aplicação sobre fundos coloridos
- [`favicon.svg`](logo/favicon.svg) — favicon vetorial da aplicação
