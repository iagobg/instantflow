# D03 — Authorized stage boards

Implemented over the shared record projection, starting from 68894ba. Workflow
names and school keys do not select application behavior. Configured board views
now render published stages in definition order, including empty stages, with
cards drawn from the same authorized section projection as other record views.
Table, calendar and assignment views retain their existing page behavior. The global
request-list board chooser navigates to this same process board; its old mixed-version
grid has been removed. The selected configured view is carried as a public view key
in the process URL, without adding another board engine.

## Read and version contracts

A board shows exactly one immutable published version. Its selector lists only
record-bearing pins with authorized visible cases, plus an authorized current
board publication even before its first case. Matching keys from different
versions never share columns or counts. Older and archived pins remain readable;
a newer role mapping does not erase access to an authorized historical board.
The shared authorized view-discovery query resolves that historical workspace.
Creation and record actions continue to enforce current permissions and pinned
runtime contracts. A historical-only workspace does not advertise an inaccessible
latest-flow link; opening a case still offers its own pinned flow.

Projections owns the shared SQL predicate, filters and field projection.
StageBoards composes those operations under Tenant's fresh authorization gate.
Record visibility, view roles, participant audience restrictions, field masks,
assignments and configured ordering/filtering use the existing owners. Card titles
use the first readable configured short/long text value, with an ID fallback.
An unreadable field cannot become a title, filter value or matching count.

The read is explicitly bounded:

- Up to 25 authorized version choices per selector page.
- Up to 10 ordered stage columns per stage-window page; all published stages
  remain reachable, including empty ones.
- Up to 10 cards per column page, so at most 100 cards are projected/rendered.
- Each nonempty visible column uses one authorized SQL LIMIT/OFFSET query;
  there are at most 10 such queries. Readable sections are projected together
  through the existing batched service, rather than queried per card.
- Ten fixed LiveView stream names hold the bounded card pages. No user input
  is converted to an atom. Refresh resets these streams, removing moved,
  inaccessible or no-longer-matching cards.

Every column distinguishes loaded cards from its total matching authorized cases.
The board total counts the selected version after user filters, including cases
outside the visible stage window and card pages. Zero means no matching authorized
case in that stage, not absence from a global 25-record page. Stage and field filters
reset card paging; changing versions also clears schema-specific stage/field and
assignment filters. Live invalidations preserve the selected version and filters,
clamp pages after moves, and recompute counts. Request list/workspace invalidations
and periodic reconciliation remain responsible for delivery and revocation.

Opening a card uses the existing case URL. No drag/drop writer or alternate
transition path was introduced. Normal guarded commands retain validation,
revision checking and idempotency. Keep a board tab open to observe a case action
from another tab; a new workspace navigation/reload starts with its normal default
view, as before this change.

## Roteiro curto em PT-BR

Use [a preparação isolada](school-demo.md). O processo continua em
[localhost:4001](http://localhost:4001/o/horizonte/processos/1) neste ambiente local;
IDs de outras instalações devem ser obtidos pela navegação normal.

1. Entre como admin@escola.example e abra o processo de requisições.
2. Em Visualização, escolha **Gargalos por etapa** e clique em **Filtrar**.
3. Confira **Versão publicada do quadro**, o cabeçalho da versão e os totais de
   cada coluna. Use a rolagem horizontal para mostrar recebimento e etapas finais.
4. Se uma etapa tiver mais de dez casos, use Anterior/Próxima dentro dela. Se o
   processo tiver mais de dez etapas, use a paginação de etapas. Esses controles
   substituem somente a página de casos/etapas consultada; não movem casos.
5. Abra um caso com Ctrl+clique para manter o quadro conectado na aba original.
   Na instalação limpa, Tintas começa em Aprovação financeira; no estado atual
   após os ensaios, Livros ocupa essa etapa. Execute uma ação que o caso oferece
   e volte à aba do quadro para observar coluna e contagens atualizadas.
6. No caso, escolha **Ver fluxo desta versão**. A etapa e versão devem corresponder
   ao caso/coluna; um rascunho do editor não altera essa publicação.
7. Em outra sessão ou após sair da conta, entre como docente@escola.example.
   O quadro mostra somente Cadernos e suas contagens autorizadas. As outras
   etapas continuam presentes, com zero casos acessíveis. Essa conta não aprova
   propostas nem reserva orçamento.
8. Retorne ao apresentador. Para comparar publicações, escolha uma versão
   autorizada no seletor e clique em Filtrar. A demo local possui apenas v1;
   os testes de versões incompatíveis/históricas são descritos abaixo.

## Actual browser evidence — 2026-10-23

At 1280 × 720, the presenter saw eight cases across seven ordered columns,
including an empty finance column. Case #2, Livros, was opened from the board
with Ctrl+click and advanced academic → finance through Aprovar proposta,
revision 3 → 4. The original board moved it into finance, removed it from academic,
marked academic empty, retained board selection and kept total eight without a
board reload. This browser comparison used the same identity in two tabs;
automated LiveView tests additionally use different identities.

[Before](evidence/demo-readiness/d03-board-before.png),
[after transition](evidence/demo-readiness/d03-board-after-transition.png),
[final board](evidence/demo-readiness/d03-stage-board.png),
[full board page](evidence/demo-readiness/d03-stage-board-full.png).

Tab reached the horizontal board region with a visible outline. Three ArrowRight
presses moved it to scrollLeft 120; horizontal scrolling reached the terminal
columns. The document itself did not overflow horizontally.
[Terminal columns](evidence/demo-readiness/d03-terminal-columns.png).

The restricted account saw one case and six empty columns, with no other cases
or counts. A finance-stage filter returned exactly one matching case for the
presenter. [Restricted board](evidence/demo-readiness/d03-restricted-board.png),
[filtered board](evidence/demo-readiness/d03-filtered-board.png),
[DOM measurements](evidence/demo-readiness/d03-rehearsal.json).

Browser inspection also found inherited preformatted whitespace expanding compact
card fields; board previews now collapse that indentation while full record detail
retains its existing formatting. The layout was rechecked after asset rebuild.
The presenter session and board were restored and left available.

No new cases, users, grants, drafts or publications were created by this D03 browser
check. Only case #2 advanced to finance. Case #3 remains purchase from D02, and
case #7's saved correction edit/draft #1 remain intact. Final stage counts are:
draft 2, academic 0, finance 1, purchase 2, receiving 1, complete 1, cancelled 1.
Setup reruns preserve this rehearsal history.

## Automated acceptance and remaining gates

StageBoards tests cover 35 draft cases plus an older review case beyond the first
25 overall, with 27 newer inaccessible cases; independent column pages and exact
counts; configured filters; empty stages/current publication; unreadable title/filter
fields and grant revocation; incompatible labels and archived pins; 15-stage windows;
27 record-bearing version choices; and another organization's scope.

LiveView tests cover page replacement without stale streamed cards, empty boards,
version switching/preservation, historical workspace access after role remapping,
permitted transitions/corrections by different users, denial without mutation,
filter preservation, and redirect/no-data behavior after process access is revoked.
The global board chooser is checked against the canonical process board. Existing
shared projection/discovery and non-board view regressions also pass.

The previously documented intermittent invalid-session failure **recurred** in an
initial full run, seed 865528, in BudgetsLiveTest at LiveViewTest.ClientProxy.put_view/3.
That early run briefly overlapped a focused test process and was stopped to serialize
validation after a test correction. It is not counted as passing, and no cause is
assigned to the overlap. See the retained
[numeric-only diagnostic evidence](evidence/demo-readiness/d03-session-diagnostic.txt).
A later instrumented run captured the immediate cause of another occurrence:
the verifier observed a signed timestamp 2907 ms ahead of its current OS clock.
Clock stability remains open; passing subsequent runs are not a fix.

The new test-only scripts/diagnose_token_clock.exs traces only numeric timestamp
and age results inside Plug.Crypto. It does not trace tokens, signatures, payloads,
keys or sessions. Source inspection found that future-dated timestamps can return
invalid, while signature/topic/static-token mismatches can also produce invalid.
The initial failure did not include numeric samples, so it cannot be attributed
to clock movement. Eight targeted repetitions passed without reproducing it.
Instrumented runs passed 371 and then 372 tests as historical access was completed.
After the global-board redirect was added, a complete 373-test run had one failure
in Sprint11CombinedRecreationTest at the same LiveView token boundary. At that
failure, the trace captured:

~~~text
TOKEN_CLOCK_INVALID signed_minus_now_ms=2907
373 tests, 1 failure
TOKEN_CLOCK_SUMMARY age_checks=1177 invalid_age_results=1 largest_future_delta_ms=2907
~~~

Both default token signing and age verification use Plug.Crypto's OS-time helper;
project source/tests do not supply signed_at overrides. This occurrence therefore
has concrete future-timestamp/clock-regression evidence. The underlying local
clock instability has not been repaired, and the earlier uninstrumented event
still has no numeric attribution. A final serial verification is recorded below;
its outcome does not establish clock stability. No dependency code, token
validation or security checks were weakened.

To investigate a recurrence using the checked-in harness:

~~~sh
MIX_ENV=test mix run --no-start scripts/diagnose_token_clock.exs test test/instantflow_web/live/budgets_live_test.exs --seed 865528 --repeat-until-failure 8 --max-failures 1
MIX_ENV=test mix run --no-start scripts/diagnose_token_clock.exs precommit --seed 865528
~~~

This checkpoint does not complete D01's enrollment/trip/incident dataset expansion,
the independent UI-only process build/publication rehearsal, or D04's release gates.
Historical version selection, card paging past 25, and multiple simultaneous
identities were verified in automated tests rather than this browser dataset.

## Final verification — 2026-10-23

- Final focused UI regression set: 18 tests, zero failures, seed 576683.
- mix assets.build passed; compilation with warnings as errors and formatting passed.
- Final instrumented mix precommit: 373 tests, zero failures, seed 865528,
  171.5 seconds. The trace observed 1186 age checks, zero invalid-age results.
- git diff --check passed.

The earlier complete 373-test run with one captured future-token failure remains
part of this report. This later successful run verifies the code checkpoint; it
neither repairs the local clock nor closes the D04 clock/session stability gate.
