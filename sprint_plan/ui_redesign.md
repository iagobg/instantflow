# UI redesign: authoring, process navigation and collaboration

[Review notes](../docs/ui-usability-review.md) · [Sprint index](sprint_index.md) · [Design](../design/index.md)

Status: Complete · Created: 2026-10-24 · Tasks: 6/6
Actual start / finish: 2026-10-24 / 2026-10-26.

## Goal

Make the generic builder and process workspace understandable for a school administrator, make the stage board directly discoverable, and make concurrency behavior legible for the seminar. Deliver a stable presentation candidate before collecting final VPS measurements or recording the demonstration.

The school demo milestone is accepted. This plan improves its usability; it does not reopen completed architecture sprints, authorize deployment, or resume customer-delivery Sprints 12–15. Implementation started with a partial browser baseline and the first authoring hierarchy increment.

## Scope and boundaries

Core: model index/editor hierarchy, contextual configuration, process/board navigation, flow readability, case action/status hierarchy and verification. Preserve shared definition/projection/runtime owners, authorization-before-pagination, version pins, bounded streams and current query budgets.

Exclude: new business capabilities, schema redesign, automatic migrations of published definitions, real integrations, customer onboarding, durable draft recovery, drag-and-drop transitions, full rebranding and a replacement graph engine.

Carry forward the relevant collaboration usability slice of S13-T02 and evidence discipline of S14-T03. Do not mark those deferred tasks complete. VPS benchmark execution belongs to the following evaluation milestone; instrumentation changes, if separately needed, must precede the candidate freeze.

## UX01 — Confirm current surfaces and baseline

- [x] Inspect model index, simple draft, complex participant draft, published editor, process workspace, board, flow and case detail in the running application.
- Capture baseline screenshots at 1280 × 720, a wider desktop and a narrow mobile viewport; include existing themes and long PT-BR labels.
- Verify what “Gargalos” represents in the actual configured definition. Record process/view keys privately as needed; navigation must depend on view type and authorization, never label matching.
- Trace the school activity authoring and two-session collaboration journeys. Record current wrong turns and defects.
- Agree a small layout sketch using existing visual tokens and the information structure in the review. Identify any current behavior already satisfying these tasks.

Acceptance: dated baseline and source revision distinguish observed UI issues from source-based hypotheses. No draft edits, publication or resets are needed just to inspect.

## UX02 — Restructure model discovery and authoring

- [x] Make creation and existing work prominent; demote import/export and technical settings without removing functionality.
- Put process title, publication/draft status and save state before all configuration panels.
- Provide navigable authoring sections: overview, form, stages/approvals, people/permissions, pages/views and review/publication.
- Move participant preview into review/testing. Use plain wording, fictional-data disclaimer and relevant empty state. No preview form with an unexplained empty page selector.
- Make item creation contextual and show only relevant parent/operational/participant controls.
- Provide linked validation summary and explanations for unavailable publishing. Preserve per-form dirty state, conflict recovery and explicit confirmation.

Acceptance: create the school activity process using typed UI controls, return to earlier sections without silent loss, correct an invalid configuration and publish. Verify published read-only state and new-version editing. Existing private participant policies remain intact.

## UX03 — Make process records and board directly discoverable

- [x] Expose a clearly labelled “Quadro de Acompanhamento” navigation action when an authorized configured board is available.
- Separate presentation selection from named views and filters. Switching presentation must not require submitting the filter form.
- Preserve configurable process pages and other supported presentation types. Handle multiple boards with bounded discovery; a board outside the first discovery page remains reachable.
- With no board, show appropriate setup guidance only to authorized authors; do not invent a board or bypass configuration.
- Store validated navigation context in URLs or an equivalent explicit mechanism: selected view, version and compatible filters/pages. Restore it after visiting a case or flow.
- Keep total versus loaded counts, empty stages, column/version paging and historical pins correct.

Acceptance: open a board directly from the process without knowing the label “Gargalos”; filter, open a card beyond the first page and return without losing context. Cover multiple/no boards, hidden views, revoked access and incompatible versions. No all-version/all-record preload to simplify navigation.

## UX04 — Improve flow orientation and readability

- [x] Retain the shared graph renderer/layout while prioritizing readable labels over technical keys.
- Clearly distinguish current case stage, selected inspection stage and latest-versus-pinned publication.
- Add accessible full-label/connection detail for stage inspection and explicit overview/current-stage recenter actions.
- Preserve corrections, terminal markers, arrow direction and accessible textual connections; never infer execution history from graph order.
- Keep scrolling contained and reader focus stable on refresh. Respect reduced motion.
- Defer fit/zoom if it risks the freeze; if included, verify legibility and keyboard operation.

Acceptance: explain initial/terminal stages and a correction path on both the simple activity flow and a larger existing process. Long labels are available without hover. Historical cases display their own version. Hidden transitions/guard internals remain hidden. Node selection, if added, works by keyboard and does not trigger transitions.

## UX05 — Unify case actions and interaction feedback

- [x] Show case identity/current stage and a compact next-action summary near the heading, respecting configured permissions.
- Make each editable section's saved, unsaved, pending and conflict states clear; distinguish reconnecting from saved.
- Explain blocked actions at the appropriate location and link to the section requiring attention where possible.
- Keep comparison/reapply/discard explicit, preserve other authorized drafts and prevent duplicate submissions.
- Apply consistent action hierarchy, labels, spacing and focus behavior across the touched index, builder, process, board, flow and case surfaces.

Acceptance: real two-session run covers independent-section saves, same-section conflict/reapply, stale approval, lost acknowledgement/retry and reconnect. Verify one business effect per accepted idempotent command and revocation handling. No claim that presence locks a form or that an enabled button guarantees guard success.

## UX06 — Acceptance, documentation and presentation freeze

- [x] Run focused affected LiveView/projection/graph tests, mix assets.build and mix precommit; inspect task help before invoking unfamiliar tasks.
- Complete authenticated browser rehearsal at 1280 × 720 and a narrow viewport, with keyboard operation, visible focus, readable contrast, long labels and loading/empty/error/denied states.
- Exercise school activity authoring through publication, direct board access, allowed/denied actions, live refresh and pinned flow. Check an existing non-school process for generic behavior.
- Check navigation/refresh query and payload bounds where changed; compare to the existing applicable budgets. Full VPS load measurements follow the freeze.
- Record revision, assets/environment, test results, screenshots, defects and known limitations. Update affected walkthroughs and this sprint/index.
- Freeze a named candidate commit only after acceptance. Record which later changes require rerunning benchmarks or re-recording video.

Acceptance: no silent draft loss, bypassed permissions, incorrect version mixing, duplicate commands, inaccessible essential controls or unbounded read regressions. Known cosmetic limitations have explicit disposition. Do not mark Done from test counts alone.

## Execution order and scope control

UX01 first. Deliver UX02 and UX03 as the highest-value slices; then UX04 core readability and UX05 collaboration feedback; conclude with UX06. Implement incrementally and preserve reviewable behavior.

Pre-freeze cut line: direct board entry, corrected builder order/context, clear case states, readable current-stage flow and acceptance evidence. Optional polish/animation/zoom and broader navigation redesign remain follow-ups. Do not schedule a large rewrite or add features to complete this sprint.

## Evidence to retain

Before/after screenshots; exact UI-only authoring script; same-section conflict and independent-section outcomes; direct board/context-restoration checks; historical/restricted projections; keyboard/mobile observations; test/build logs and candidate commit.

## Progress

6/6 task groups complete. Each checkbox represents its task group. See [final acceptance, limitations and freeze rules](../docs/ui-redesign-acceptance.md), [baseline](../docs/ui-redesign-baseline.md) and [increment evidence](../docs/ui-redesign-first-increment.md). Named local candidate: ui-redesign-candidate-2026-10-26. No deployment or VPS benchmark execution is included.

## Planning-change validation — 2026-10-24

Documentation-only change. Local link validation and git diff --check passed. Required mix precommit ran 381 tests with one failure (seed 564473): an existing Sprint09ReviewAcceptanceTest fixture insertion exceeded the 15-second database connection ownership timeout. The exact affected test at line 200 passed on a focused rerun with the same seed. The full run is retained as failed; the focused pass does not establish or fix its root cause. Logs: /tmp/instantflow-ui-plan-precommit.log and /tmp/instantflow-ui-plan-recheck.log. No application or test code was changed. This validation does not satisfy UX06 or mark any implementation task complete.
