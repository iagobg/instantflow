# UI redesign presentation candidate — 2026-10-26

Candidate name: ui-redesign-candidate-2026-10-26. Base revision: 8091b975fac29b6e19490d20f1958080af3ced0f. This is a local Git commit/tag, not a deployment. Resolve the exact candidate with git rev-parse ui-redesign-candidate-2026-10-26.

## Acceptance evidence

| Area | Outcome and method |
| --- | --- |
| Authoring | Browser: typed school-activity creation, field/role configuration, independent pending forms, invalid participant configuration corrected, explicit publication, published controls and new-version clone. Preservation/private-policy tests pass. |
| Navigation | Direct configured list/board/assignment/calendar selection; browser board → ticket → pinned flow → return retains context. Integration covers historical second-card-page and second-discovery-page restoration. No board is fabricated. |
| Flow | Desktop/mobile keyboard overview/current-stage controls, full selected connections and distinct actual/inspected stages. Pins and restricted projections retained; inspection executes no transition. |
| Collaboration | Browser peer conflict/comparison/reapply/save and actual server disconnect/reconnect preserve drafts without automatic submission. Separate-actor LiveView integration covers independent sections, revocation, stale data and recovered lost-acknowledgement retries with one effect. |
| Restricted identity | Teacher saw only its single permitted ticket, without approval/reservation actions. Direct access to admin rehearsal record 33 redirected with an access-denied message. Admin login restored afterward. |
| Generic process | Existing restaurant setup, products, visits, batches, printing/settlement and pinned/paged navigation exercised through integration tests, not a separate browser restaurant rehearsal. |
| Bounds | Existing authorization-before-pagination and query-count checks pass. Projection owners unchanged. Discovery: 25 views/page; board: ten stage columns and ten cards/stage. Navigation hints are allowlisted and capped: scalar values 500 bytes, nested keys 100 bytes, field filters 20, column pages ten. Runtime owners reauthorize hints. Guidance/inspection adds no database reads. |
| Visual/input | Representative 1280 × 720, 1440 × 900 and 390 × 844 samples across both themes; long labels, keyboard focus, empty/denied/conflict/disconnected states. Not every surface in every size/theme combination. |

Chronology and screenshots: [increment evidence](ui-redesign-first-increment.md), [baseline](ui-redesign-baseline.md). The original pre-edit screenshot matrix is incomplete; later captures are identified as current-working-tree evidence, never retroactively labelled before images.

## Validation

Latest application-change full run: 387 tests, zero failures, seed 140374, 207.0 seconds. Final targeted generic/query-bound suites: 19 tests, zero failures, seed 140557, 13.8 seconds. Final candidate results are appended after the last check.

No runtime domain, migrations, authorization policy or graph engine changes. VPS load measurements belong to the next evaluation milestone. Navigation adds bounded URL text to rendered links; no claim of byte-for-byte identical payloads or a new measured VPS payload budget is made.

## Known limitations and disposition

- Mobile global navigation remains tall; essential controls remain reachable by scrolling/keyboard. Compact navigation is deferred polish.
- SVG labels may truncate; full selected details and the textual list work without hover. Zoom/fit is deferred.
- Some invalid configuration messages use schema paths. Pending values survive correction/discard; clearer copy is deferred polish.
- Existing requisition draft is labelled Solicitada. Renaming requires a future publication; historical definitions are preserved.
- Drafts are local to the active tab, not durable storage. Reapplication is explicit and whole-form.
- Earlier parallel runs hit SQL sandbox ownership timeouts. Final checks use one test case at a time; this is not a root-cause fix. Existing migration-module redefinition warnings remain.
- This is an agent-led synthetic rehearsal, not independent usability research or production certification.

## Reproduction and freeze rules

Restart the isolated web-4003/PostgreSQL-55435 demo with its existing private .local/my-demo/env; do not seed/reset for ordinary rehearsal. Credentials are excluded here. Use the updated [school walkthrough](school-demo.md).

Record the resolved candidate in subsequent benchmark/video reports. Changes to routes, queries, authorization, projections, client hooks or assets require affected acceptance checks and fresh measurements. Visible UI/copy/demo-state changes require reviewing screenshots and re-recording affected video segments. Commit instrumentation changes before new benchmarks; never reuse measurements from another revision without explicit qualification.

Unrelated design/seminar/review work remains outside this candidate. No remote push or deployment is included.

## Final candidate check

Final mix precommit --max-cases 1: 387 tests, zero failures, seed 827222, 184.2 seconds. Asset build, whitespace checks and local links in all four redesign evidence/plan documents passed. Logs: /tmp/instantflow-ux06-precommit.log, /tmp/instantflow-ux06-assets.log, /tmp/instantflow-ux06-bounds-generic.log.

Built asset SHA-256:
- app.js: ab22eb43852c86359104f14fb47b6eb8e443c95c32f2ab8ca9d19f9e62297010
- app.css: f604dda3ccd5f80ab695601764e940cc15984577a108ebf9c7122441c09b6e50

All six sprint groups accepted with the stated evidence methods and limitation dispositions. Candidate branch: codex/ui-redesign-candidate-2026-10-26; tag: ui-redesign-candidate-2026-10-26. Generated build output and private demo settings are not committed; build from the candidate sources.
