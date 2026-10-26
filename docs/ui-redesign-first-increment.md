# UI redesign — first authoring increment

Started 2026-10-24; resumed 2026-10-25 after a usage-limit interruption.
Base revision: 8091b975fac29b6e19490d20f1958080af3ced0f, with existing uncommitted design, sprint and seminar documentation preserved. This is an internal agent rehearsal, not independent usability testing.

## Observed baseline

Authenticated local demonstration, Escola Horizonte, administrator account. Inspected model index, the existing simple activity draft, requisition process, its configured board, case detail and pinned flow. No draft edit, publication, reset or business action was submitted during baseline inspection.

- At 1280 × 720, creation and JSON import share the first row, placing existing drafts below the fold.
- The activity draft opens with a participant preview and an empty page selector. Its title is below the first viewport; page composition precedes basic identification.
- Selecting “Gargalos por etapa” and submitting Filtrar renders the configured stage board. It is a real board, not a label to match in navigation code.
- Board → case → pinned flow → Voltar aos casos returns to the default list and loses board selection.
- Pinned flow already identifies the case version and current stage, and provides full stage/connection labels in a textual list. Preserve those features.
- At 390 × 844, the global navigation occupies much of the first viewport. The pinned flow heading wraps, and its graph lies farther down the page.
- A [1440 × 900 index screenshot](evidence/ui-redesign/before-index-1440x900.png) was retained before edits. Other baseline captures are available in the chat tool outputs, not as repository image artifacts.

Baseline coverage is partial: complex participant draft, published editor, both themes across all target sizes, and two-session collaboration still require inspection. UX01 remains unchecked.

## Implemented increment

- Existing drafts beside process creation; JSON import remains available in a native disclosure.
- Editor title, publication/draft identity and current local-edit status precede configuration.
- In-page section links preserve mounted forms; metadata and role mappings precede graph and item editing, followed by page composition and review.
- Participant preview moved into review with plain wording and a fictional-data disclaimer. Without configured participant pages, show setup guidance instead of an unusable form.
- Existing form IDs, events, publication confirmation, authorization, definition owners and streams retained. No schema changes; record presentation selection now uses the existing authorized discovery and query owners.

The resumed authoring increment adds independent pending-form preservation, explicit per-form discard, linked validation, contextual item-parent selectors, and server-side publication blocking while forms are unsaved or conflicted. Saving identification no longer clears an independently edited page. Operational/participant page controls still need contextual organization, so UX02 is not complete.

UX03 now provides direct presentation buttons labelled by configured type (including Quadro por etapas), separate from submitted filters. Buttons use the existing paginated authorized discovery; no additional record preload or query was introduced. View-selection tests now exercise these controls, including historical authorization. URL context restoration, no-board author guidance and full multi-page acceptance remain. No candidate commit is frozen.

## Validation

The interrupted template closing-tag error was repaired on 2026-10-25. Formatting and mix assets.build pass. Full mix precommit and focused reruns are recorded below when complete. The local server stopped during the interruption and was restarted with its existing .local/local-demo-server.exs database selector; no seeding or reset was performed. That initial login blocker was resolved by the isolated demo described below.

Initial full precommit: 381 tests, 1 failure, seed 35009. The document fixture exceeded the 15-second SQL sandbox ownership limit during staff insertion (test/instantflow/enrollment/documents_test.exs:47). Focused rerun of that test and the authoring suite: 12 tests, 0 failures (1 excluded), same seed. This does not establish the underlying timeout cause. Logs: /tmp/instantflow-ui-first-slice-precommit.log and /tmp/instantflow-ui-first-slice-focused.log.

Full rerun: mix precommit --max-cases 1 --seed 35009 passed, 381 tests, 0 failures (176.6 seconds). Log: /tmp/instantflow-ui-first-slice-precommit-serial.log. The original parallel timeout remains an unresolved contention observation; serial success is not a root-cause fix. git diff --check passed. The browser viewport override was reset and the restored demo login tab retained for the next authenticated check.


## Authenticated continuation — 2026-10-25

The isolated demo on port 4003 uses its own PostgreSQL instance on 55435 and private restart environment at .local/my-demo/env. Existing demo data was not reset. Database credentials are intentionally omitted here.

Browser rehearsal created the school activity process using typed controls, saved identification while preserving an independently edited page, confirmed that a pending page prevents switching to a new page, saved the page and a date field, mapped local roles, and explicitly confirmed publication. Published draft 1 is read-only through its save controls; cloning it creates editable draft 2. Complex enrollment draft 3 was inspected with its participant preview inside review. Captures include dark desktop and narrow mobile; the full both-theme acceptance matrix remains pending.

Direct navigation was verified in the requisition process: selecting Quadro por etapas · Gargalos por etapa immediately renders the authorized version-1 board with eight cases. The filter form retains only search, version, stage and configured filters; presentation selection is outside it. No business transition was executed in this check.

Screenshots: [published authoring at 1280](evidence/ui-redesign/authoring-dark-1280.png), [mobile authoring](evidence/ui-redesign/authoring-dark-mobile.png), [direct board](evidence/ui-redesign/direct-board-dark.png).

The initial focused navigation run found an outdated test that still submitted the removed view selector (20 tests, 1 failure). All affected tests now select the direct presentation controls; this was a test migration, not an application crash. Full resumed precommit result is recorded below.


Additional browser checks: direct selection by Enter works at 390 × 844; the long board label wraps inside its button. The [light-theme 1280 × 720 capture](evidence/ui-redesign/direct-board-light-1280.png) and [mobile capture](evidence/ui-redesign/direct-board-mobile.png) retain the controls and filter hierarchy. The field-trip calendar remains selectable directly and displays its six dated records. The original dark-theme preference was restored. The mobile global-navigation footprint remains a known layout limitation.

First full resumed validation: mix precommit --max-cases 1 passed, 383 tests, 0 failures, seed 32502, 183.7 seconds. Log: /tmp/instantflow-ui-resume-precommit.log. A final follow-up run covers the distinct Calendário and Atribuições labels. Asset build passes. These results do not complete the two-session acceptance matrix or authorize a candidate freeze.

Final validation after all application changes: mix precommit --max-cases 1 passed, 383 tests, 0 failures, seed 343630, 181.5 seconds. Log: /tmp/instantflow-ui-resume-final-precommit.log. mix assets.build and git diff --check passed. Existing migration-module redefinition warnings appeared during migration tests. No candidate commit or deployment was made.

## User-directed navigation refinement — 2026-10-25

Consolidated the records presentations and process-flow link into one navigation row above the records panel. Labels are Lista, Quadro de Acompanhamento, Atribuições, Calendário when available, and Fluxo do Processo. Configured names appear only when multiple views of the same type need disambiguation on the current discovery page. The write action Iniciar registro stays inside the panel. The redundant sole records-page link is hidden; multiple configured pages and operational-page navigation remain available.

Browser verification confirmed direct board selection and keyboard switching back to Lista at 390 × 844. Desktop navigation fits one row; mobile wraps into two without clipping. Screenshots: [desktop](evidence/ui-redesign/process-navigation-consolidated.png), [mobile](evidence/ui-redesign/process-navigation-mobile.png).

Investigated the reported initial ticket status: requisition.json declares initial key draft with label Solicitada, and a separate submit transition (Enviar para análise) to academic (Aprovação da área), with required request fields. Creation is therefore not submission. Recommended renaming the initial label to Rascunho in a subsequent workflow version; no published definition or existing ticket version was changed in this layout refinement.

Refinement validation: mix precommit --max-cases 1 passed (383 tests, 0 failures, seed 380028, 181.5 seconds); mix assets.build and git diff --check passed. Log: /tmp/instantflow-ui-navigation-precommit.log.

## Navigation context and UX01 closure — 2026-10-25

Bounded navigation hints now travel through process, ticket and pinned-flow URLs. View selection, compatible filters, configured page, selected publication and per-column/page positions are restored through the existing authorized query owners. Record interactions patch the URL instead of performing an extra pre-patch query. No arbitrary return URL is accepted. Runtime owners still determine accessible views, versions and records; navigation hints do not confer access.

The browser verified board → filtered card → pinned flow → board with query 1 and version 1 retained. The regression test covers an older publication with eleven cases, the second card page, a process-name filter, and the same return journey. Focused board/flow validation: 13 tests, 0 failures (seed 771317). Full mix precommit --max-cases 1: 384 tests, 0 failures (seed 248942, 227.6 seconds); mix assets.build and git diff --check passed. Logs: /tmp/instantflow-navigation-context-focused.log, /tmp/instantflow-context-precommit.log and /tmp/instantflow-context-assets.log. Existing migration redefinition warnings remain in the full-run output.

UX01 inspection is complete; see [dated inventory, journeys, defects and evidence limitations](ui-redesign-baseline.md). UX02/UX03 remain in progress. No candidate commit or deployment was made.

## Contextual authoring — 2026-10-25

Page configuration now shows settlement controls only for settlement blocks, operational role controls only for operational blocks, and financial configuration when a financial block or existing account binding requires it. The participant toggle remains available; detailed audience/field/document/action controls appear only when enabled. Operational terminology is a secondary disclosure and opens when that form has pending edits. Hidden controls remain mounted and serialized, preserving their values. This does not change projection policy, schema or runtime permissions.

The shared checkbox style now overrides full-width text-input sizing with a native 20 px checkbox. Desktop/mobile screenshots: [contextual controls](evidence/ui-redesign/ui-contextual-page-controls.png), [mobile](evidence/ui-redesign/ui-contextual-page-mobile.png).

Browser rehearsal on existing editable demo draft 2: enabled participation, observed the settings appear, attempted to save without an audience, received a validation error with the pending form retained, disabled participation and saved successfully. Publication availability returned to ready. No new publication or access grant was made. The validation error still uses a schema path; plain-language field-specific error copy remains a polish item. All forms were saved before leaving the browser.

Focused regression: 14 authoring tests, 0 failures, seed 312688. New coverage verifies that participant selections survive disabling/re-enabling the settings and saving identification independently. Earlier evidence covers typed school-activity creation, navigation without draft loss, role mapping, explicit publication, published save controls and cloning for new-version editing.

Validation recovered on 2026-10-26 after the usage interruption: contextual authoring full precommit passed, 385 tests, 0 failures, seed 225428, 224.1 seconds. Asset build and diff checks passed. UX02 is accepted based on this run, focused preservation coverage and the recorded browser authoring/correction/publication rehearsals. Technical validation wording remains a known polish item. Log: /tmp/instantflow-contextual-authoring-precommit.log.

## Remaining board discovery cases — 2026-10-26

Added author-only setup guidance when the current discovery page has no board. With multiple discovery pages, the message first points to the other pages; it does not claim no board exists elsewhere. Guidance links to the authorized model editor and never synthesizes a board. The simple school-activity process was inspected in the browser: setup guidance appears for the administrator, without a board button. [Capture](evidence/ui-redesign/board-setup-guidance.png).

Regression coverage publishes two generations of twenty distinct views. Two historical boards fall beyond the first 25-view discovery page; both retain their names for disambiguation, open the correct historical publication and restore page 2 and the selected board after a ticket round trip. A separate check confirms ordinary requesters do not see setup guidance. Existing coverage retains historical access, empty stages, independent card/column paging, live refresh, denials and version switching.

Focused board suite: 10 tests, 0 failures, seed 713390. The new UI uses the existing bounded discovery result and adds no database reads, full-record preloads or all-version fetches. View discovery remains 25 entries per page, stage windows remain bounded and card streams remain limited to ten per stage.

Final board-discovery validation: mix precommit --max-cases 1 passed, 387 tests, 0 failures, seed 118489, 216.9 seconds. mix assets.build and git diff --check passed. Logs: /tmp/instantflow-board-discovery-precommit.log and /tmp/instantflow-board-discovery-assets.log. UX03 is accepted based on direct-navigation/browser evidence, historical/paging round trips and existing authorization/version regression coverage. UX04, UX05 and final UX06 acceptance remain pending; no candidate freeze or deployment occurred.

## UX04 flow orientation — 2026-10-26

Added explicit Visão geral and, for pinned case flows, Voltar à etapa atual controls. The actual ticket stage is displayed separately from the inspected stage. Selected-stage details show full authorized incoming/outgoing connection labels and destinations, initial/terminal status, and an explicit statement that selection does not change the record. Technical keys no longer compete with stage labels inside graph nodes. The shared renderer, graph layout, arrows, correction paths, version pins and full textual stage list remain intact.

Browser rehearsal: the simple activity flow identifies Em preparação as initial and Concluída as terminal; it has no configured correction transition, and none was invented. On pinned requisition record 33, inspecting Aprovação da área retained actual stage Solicitada and displayed the full Revisar proposta e renovar aprovações return path. Keyboard overview reset diagram scrollLeft/scrollTop to zero and removed inspection highlighting. Keyboard current-stage action restored inspection of Solicitada. Mobile inspection of Aprovação financeira showed full wrapped connection text and visible keyboard focus. No business transition was executed.

Captures: [simple flow](evidence/ui-redesign/ui-flow-simple-inspection.png), [current versus inspection](evidence/ui-redesign/ui-flow-current-versus-inspection.png), [mobile details](evidence/ui-redesign/ui-flow-inspection-mobile.png).

Focus remains server-owned; ordinary refresh does not emit a recenter event. Existing client behavior confines panning to the diagram and honors prefers-reduced-motion. No new zoom/fit behavior or graph engine was introduced. The existing small SVG label truncation remains, with full selected details and the full textual list available without hover. Optional zoom is deferred.

Focused flow regression: 5 tests, 0 failures, seed 127742. Coverage explicitly distinguishes inspection from current stage, verifies overview/current controls, and retains historical pins, live stage updates and restricted-flow checks.

UX04 final validation: mix precommit --max-cases 1 passed, 387 tests, 0 failures, seed 468374, 211.0 seconds. mix assets.build and git diff --check passed. Logs: /tmp/instantflow-ux04-precommit.log and /tmp/instantflow-ux04-assets.log. UX04 core orientation is accepted; optional zoom remains deferred. UX05/UX06 remain open, with no candidate freeze or deployment.

## UX05 case actions and collaboration feedback — 2026-10-26

Case identity is followed by a compact next-action summary. Its links lead to the existing confirmation controls; they do not execute commands. Pending forms and conflicts have direct links, blocked actions explain the prerequisite review/save work, and every section distinguishes unchanged loaded revision, local draft, conflict and read-only state. Submitted forms show an awaiting-confirmation indicator while LiveView reports submission in progress.

The connection hook now announces disconnected/reconciling/reconnected states separately from save status. Existing offline blocking and reconcile-before-enabling behavior are unchanged. Conflict panels use theme tokens rather than a fixed light fill, fixing the observed unreadable dark comparison.

Browser rehearsal used two independent LiveView tabs under the same administrator account on existing rehearsal record 33: competing drafts, remote save, summary link to conflict, explicit comparison, explicit reapply, save and peer refresh all succeeded. The comparison is readable in dark mode. Then the isolated port-4003 server was briefly stopped and restarted with the existing private environment (no seed/reset). The local unsaved reconnect draft survived, authoritative save controls were disabled while disconnected, and the peer retained the previous saved value after reconnection. No automatic mutation occurred. The reconnect-only draft was explicitly discarded; the peer tab was closed and the original dark theme/viewport restored. The server remains running.

Coverage distinction:
- Browser: same-section conflict/reapply, peer refresh, real transport disconnect/reconnect, no automatic save, desktop dark and mobile light layout/focus.
- Real LiveView integration sessions with separate actors: independent-section saves, same-section comparison, stale-action blocking, protected-draft revocation and preservation of other authorized drafts.
- Lost acknowledgement: the integration suite recovers the original command key, retries, and asserts exactly one save event with no extra ticket revision. This is controlled integration fault injection, not a browser network-loss simulation.

Focused collaboration suite: 6 tests, 0 failures, seed 410476. Full precommit recovered after interruption: 387 tests, 0 failures, seed 140374, 207.0 seconds. Asset build and diff checks passed. Logs: /tmp/instantflow-ux05-focused.log, /tmp/instantflow-ux05-precommit.log, /tmp/instantflow-ux05-assets.log.

Captures: [case summary](evidence/ui-redesign/ui-ux05-case-summary.png), [dark conflict comparison](evidence/ui-redesign/ui-ux05-conflict-dark.png), [mobile light](evidence/ui-redesign/ui-ux05-case-mobile-light.png).

UX05 is accepted with the coverage methods above explicitly distinguished. Final cross-surface UX06 acceptance, known-limitation disposition and candidate freeze remain pending. No deployment or candidate commit was made.
