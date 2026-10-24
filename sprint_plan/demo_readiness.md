# School demo readiness and execution plan

Status: In progress — D01 purchasing checkpoint and D02 flow implementation · Assessed: 2026-10-23

[Sprint index](sprint_index.md) · [Design](../design/index.md)

## Goal and scope

Demonstrate one fictional school with an administrator, several configured processes and believable ongoing cases. A presenter must be able to build and publish a process, explain its flow, inspect its cases on a stage board and act on a case using the same authorization and commands as any other user.

A process is the configured workflow; a case is one running instance. The board belongs to the process and contains cases. Flow describes stages and transitions, not a second execution engine.

Sprints 12–15 are deferred, with their customer-delivery requirements preserved. This milestone uses synthetic data and simulated integrations in an isolated local demo database. It does not require customer onboarding, real email/payment/printing, production hosting, or a restaurant expansion. It must preserve the generic contracts proven by Sprints 09–11.

## Assessment: sound foundation, incomplete presentation

The application can support a guided technical preview today. It is not yet ready for the requested populated, convincing school demonstration. The missing work is mostly demo fixtures and shared presentation, with authorization and version-aware query work needed for a correct board; it is not another architectural rewrite.

| Demo requirement | Evidence now | Remaining work |
|---|---|---|
| School administrator and isolated organizations | Existing seeds create Horizonte/Aurora and local memberships. Current browser is authenticated as Administração. | Explicit, documented demo process grants; restricted comparison account; deterministic startup. Admin alone does not imply access to all cases or confidential fields. |
| Builder and publication | Model screen offers configurable templates, drafts, cloning and publication. Sprint 11 recreation acceptance covers supported contracts. | Rehearse an understandable UI-only build, publish and create-case story with meaningful PT-BR labels. |
| Flow visualization | TemplateLive renders an SVG graph with nodes, edges and focus. | Read-only published-flow view accessible from the process workspace, with correct version context. Reuse graph layout/presentation. |
| Stage board | Views.search uses the shared authorized projection service. records_block renders cards. For board type it only applies operations-tables CSS grid. | Real stage columns, counts, empty stages, bounded loading and useful card identities. Current card grid is not a Kanban board. |
| Ongoing school cases | Current enrollment workspace visibly has four cases, all Rascunho; three student-name previews are blank. Seed publishes purchasing/trip/incident examples but does not populate those cases. | Curated cases distributed through meaningful stages, with valid history, values, assignments and safe sample documents where relevant. |
| Interaction and permissions | Existing record routes, runtime commands, scoped projections and granular policies are reusable. | Prove board → case → allowed transition → refreshed board, including forbidden actions, restricted fields and another user's update. |

Evidence inspected: authenticated local model/enrollment UI; priv/repo/seeds.exs; lib/instantflow_web/components/process_components.ex records_block; lib/instantflow_web/live/process_live.ex load_records; lib/instantflow/workflow_catalog/views.ex; TemplateLive graph; docs/sprint11-final-acceptance.md and the independent completion review. Current DB observations describe this local demo only. No new end-to-end board or builder acceptance was run during this planning assessment. Prior 346-test precommit success establishes a regression baseline, not visual demo readiness.

## D01 — Reproducible school scenario

- [x] Provide a checked-in setup/start guide and demo fixture entry point targeting an explicitly named isolated demo database. Refuse production or unspecified reset targets. Preserve existing working databases; reset must be explicit and confined to the disposable demo. Do not rely on untracked .local scripts or commit credentials.
- [ ] Seed Horizonte with enrollment, purchasing, trips and a small confidential incident scenario through supported definitions, bindings and runtime commands. Suggested presentation dataset: 12 enrollments, 8 purchase requests, 6 trips and 3 fictional incidents. Include open work across at least three applicable stages, completed cases and a valid correction/return path. Use fixed fixture identities and idempotency keys; repeat setup must not duplicate cases or replay effects.
- [ ] Fill meaningful titles, dates, descriptions, departments and supported assignment/urgency fields. Create history through valid commands, never direct stage updates. Populate budget/document prerequisites for paths that require them. Use only fictional people and harmless documents; simulate all external effects.
- [ ] Give the presenter administrator explicit grants required for the selected non-confidential demonstration paths. Provide at least one restricted staff account and, if presenting the family portal, a participant account. Document the allowed/denied actions and fields. Confidential incidents must remain limited to explicitly authorized people, including when the presenter is an administrator.
- [ ] Output an inventory of process versions, case counts/stages and available demo roles. Validate a clean setup and repeat setup. Preserve old pinned cases rather than silently rewriting them; do not let retired fixtures become the primary demo story.

Acceptance: fresh local setup gives a populated school without manual DB edits, existing setup rerun is safe, and the presenter can see the intended processes with meaningful case cards. Fixture failure is explicit, not silently skipped.

### D01 implementation checkpoint — 2026-10-23

The [isolated setup and PT-BR walkthrough](../docs/school-demo.md) now provide
an explicit instantflow_demo target and guarded setup/reset entry point. The first
scenario contains eight purchasing cases across seven stages, including partial
receipt, completion, cancellation and a valid return for revision. Explicit
presenter and restricted-requester grants use existing policies; case mutations
use runtime commands. Clean and repeat setup passed locally; regressions cover
rerun preservation, authorization and retired pinned versions. Enrollment, trips,
confidential incidents and their documents/roles remain pending. D01 is not yet
complete. D02 progress is recorded below; D03–D04 have not started. Validation: mix precommit passed with 350 tests,
zero failures (seed 487092); isolated demo HTTP login smoke passed on port 4001.
No authenticated visual rehearsal was claimed.

## D02 — Published process flow

- [x] Add an obvious flow entry from the process workspace, retaining a clear path back to cases and the builder for authorized authors.
- [x] Extract/reuse graph layout and display where appropriate. Render stage names, initial/terminal stages, allowed graph connections and correction paths from the published definition. Keep editing authorization separate from viewing authorization; do not expose private bindings, guard internals or secret configuration through a diagram.
- [x] Show publication/version identity. A case's flow uses its pinned version and can highlight its current stage. Do not depict historical cases against the latest edited draft. If the process overview selects a version, label it explicitly.
- [x] Make large flows usable through scrolling/focus and a readable accessible alternative. Keep PT-BR labels and clear loading/empty/denied states.

Acceptance: a user can explain a published process without opening the editor; its stages match the corresponding board/version. Opening a case from an older version shows its own correct flow.

### D02 implementation checkpoint — 2026-10-23

Process workspaces now link to a read-only published flow. Record links resolve
through the shared authorized projection and retain their immutable version pin,
including archived versions; the current stage is marked in the diagram and its
readable alternative. The workspace overview explicitly shows the latest published
version and updates on publication while an open case remains pinned. The editor
and viewer share the streamed graph component and layout. Authoring navigation
remains admin-only. No bindings, guards, field values or action configuration are
returned by the diagram projection. Actor-private history connections are omitted
from overviews and shown in cases only through the runtime's existing history policy.

A follow-up [visual rehearsal](../docs/demo-flow-visual-rehearsal.md) passed for the
purchasing scenario at 1280 × 720. It verified diagram selection/keyboard scrolling,
readable labels, presenter/staff navigation, a guarded transition, another open tab's
stage refresh, allowed edits, empty search and denied foreign-case access. It found
and fixed initial positioning of later-stage cases: the graph now centers the current
stage on mount. Real screenshots and the exact resulting local state are retained.
The earlier browser approval-service limit did not recur. Post-rehearsal validation:
mix assets.build and mix precommit passed (360 tests, zero failures, seed 949960).
Focused tests
cover current/pinned publications, corrections and other-user refresh, revocation,
confidential-case denial, participant/tenant isolation, long labels and editor reuse.
Validation: the focused flow/editor suite passed (20 tests, zero failures, seed
830214), mix assets.build passed, mix precommit passed (360 tests, zero failures,
seed 636776), and git diff --check passed. See [the current flow walkthrough](../docs/school-demo.md#fluxo-publicado-d02).

## D03 — Genuine authorized stage boards

- [ ] Render board views as ordered stage columns from the applicable published definition, including empty stages, with cards containing a useful authorized title, stage, and configured fields. Preserve table/calendar behavior. School names or workflow keys must not select special code paths.
- [ ] Define version grouping explicitly: separate incompatible pinned schemas by version or offer a visible version selector. Do not merge same-named stage keys from incompatible versions. Preserve access to authorized older cases.
- [ ] Reuse Projections/Views and PolicyQuery for membership, visibility, field masking, filtering and counts. Keep SQL authorization before pagination and bounded card loading. Use per-column paging/load-more or an equally explicit bounded strategy; do not label a column empty because its cases fall outside a single global page. Distinguish loaded count from total matching authorized cases.
- [ ] Clicking a card opens its existing case experience. Keep edits/transitions in that authorized experience initially: drag-and-drop is optional and not required for demo acceptance. Any later board transition must call the same guarded runtime command, retain validation/concurrency/idempotency behavior and reject illegal moves.
- [ ] Refresh affected columns/counts after successful transitions, corrections and other-user updates. Preserve filters and handle revocation and stale writes without leaking cards or silently losing edits. Use bounded LiveView streams and clear loading/error states.

Acceptance: cases genuinely occupy the correct columns, a permitted transition moves a case once, a denied action cannot mutate it, a correction returns it correctly, and another connected session sees the update. Test a case beyond the first 25 results, empty columns, filters, restricted counts/fields, tenant isolation and incompatible published versions.

## D04 — Rehearsal and release of the demo

- [ ] Write a short PT-BR presenter walkthrough: login → school/process overview → populated board → published flow → open/edit/advance a case → observe board update → restricted-user comparison.
- [ ] Include a builder proof: create an independent process from a supported starter, change fields/stages/transitions and configure a board through the UI, review local bindings, publish, create and advance a case, then find it on the generated board/flow. No JSON or application-code changes should be needed for that supported scenario. Do not present seeded definitions alone as proof of builder usability.
- [ ] Exercise each of the four school examples briefly, with a deeper enrollment or purchase narrative. Keep any confidential demo optional and explicitly authorized. Prove the new shared flow/board also works for the independent builder-created process.
- [ ] Verify desktop layout at the actual presentation size, keyboard navigation, long labels, useful empty/error states and page reload/login stability. Investigate the documented intermittent invalid-session observation if reproduced; repeated passing reruns alone do not resolve a reproduced defect.
- [ ] Run focused fixture/projection/LiveView regressions and mix precommit. Record commit, isolated DB/setup procedure, browser evidence, test outcomes, remaining limitations and exact rehearsal script. Do not declare completion from test counts alone.

Acceptance: a clean setup plus the entire presenter script succeeds without developer intervention, direct database changes, unexplained reloads or permission bypasses. Capture real UI evidence of the populated board, flow and transition outcome. Leave the local session available for the user's inspection.

## Execution order and boundaries

Start D01 with a small valid scenario, then implement D02/D03 against it; expand fixtures and complete D04. Each checkpoint should be independently reviewed before claiming the milestone complete. No time estimate is asserted before implementation.

Keep reusable UI in shared components, queries in existing projection owners and mutations in the runtime. Fixtures supply school-specific content, not application behavior. Avoid a parallel school dashboard engine, administrator bypass, new legacy compatibility path or unbounded client-side board. Resume customer Sprints 12–15 only on an explicit priority decision after this demo milestone.
