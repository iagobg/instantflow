# Sprint 10 — Generated participant experiences and reusable projections

[Sprint index](sprint_index.md) · [Shared roadmap](first_customer_roadmap.md) · Status: Planned · Dependencies: corrected Sprint 09; D-06–07, D-11, D-25–29

Goal: recreate the school examples' authorized participant experiences through configured pages and bounded reusable capabilities, removing their dependence on process-key-selected screens. Completion enables the cross-domain acceptance gate in Sprint 11; it does not enable customer launch.

Specification: [modularity review](../docs/modularity-review.md), [school reference behaviors](../design/06-school-templates.md) and [process composition](../docs/process-composition.md).

## Tasks

Use the [builder architecture contract](../docs/builder-architecture-contract.md) established in S09-T05 and the [corrected Sprint 09 contracts](../docs/sprint09-review-resolution.md). Each task includes its own cohesive context/UI boundary and extends the recreation fixtures.

## Execution order and checkpoints

1. Start T02 by defining and implementing the shared bounded query/projection service for the first participant experience. Specify supported filters, stable ordering, limits, count semantics, pinned-version projection and permission checks. An interface wrapping load-all-then-filter is not completion of this step.
2. Deliver one independently named participant correction/document workflow through T01, with its authoring controls, local mappings, generated entry/navigation and record page. Exercise two unrelated participants, a subject with no record access, a parent with an explicitly granted staff role, revocation/reconnect and a second publication. Record this working slice and review it against the architecture contract before expanding the remaining surfaces. This is an implementation/evidence checkpoint, not an additional user-approval requirement.
3. Finish the configured T02 views and T03 finance/reset surfaces, then T04 communications and the four school recreation scenarios. Add policy and composition tests with each surface; do not defer them to the final recreation run.

Preserve existing task IDs and counts. Tasks remain open until their definition, editor/import, local setup, authorized query/command, generated UI and applicable regression checks work together. Resolve unsupported combinations with actionable validation rather than publishing a configuration that cannot be operated. Sprint 11 owns broader load measurement, residual old read paths and full preservation acceptance; Sprint 10 owns bounded reads for every surface it introduces or migrates.

Sprint 09 regressions are prerequisites throughout: explicit candidate_roles distinct from access; the same eligibility in picker/create/verify; current role/department and relationship checks; subject-only references without access grants; and parent/external identities with scoped staff grants. Do not infer participant or screen behavior from a base membership role, example key, field name or organization slug. Keep pinned legacy exceptions behind the documented adapters.

## Implementation tasks

- [ ] S10-T01 Generate external participant pages from declared projections.
  - Specify the audience and authorization of each projection separately from the page's visibility. Page/block configuration never grants underlying record, section, file or command authority. Project on the server before rendering or broadcasting; hiding a block in the browser is not authorization.
  - Provide generated discovery/entry and navigation for authorized participants, including users who cannot create records; record creation permission must not be the only route to their existing work. Read-only subjects remain absent unless independently authorized. Test direct links and list/count metadata as well as the detail page.
  - Extend the shared interface schema/editor with bounded participant-facing status, allowed fields, requested actions, documents and curated messages using the relationship policies from Sprint 09.
  - Generate organization/process-bound URLs and UI through common renderers; no EnrollmentLive selection, guardian-role screen special case or school field names in the generated path.
  - Allow only explicitly authorized projection data in HTML, history, notifications and live payloads. Reconnect and revocation must reauthorize and clear protected state; previews use synthetic fixtures under the same policy engine.
  - Preserve version pinning and compatibility for existing guardian links and enrollment URLs. New external participation remains invitation-based; anonymous signup/uploads are not introduced.
  - Resolve existing records and their actions using their pinned definition after a new publication changes or removes a page, field or stage. Define a safe route fallback without substituting current-version permissions or breaking access to old records. Clear protected streams, retained forms and pending uploads when authority is lost.

- [ ] S10-T02 Replace specialized dashboards with configured views.
  - Declare bounded filters, sorting, stage/assignment/urgency projections, columns and visibility in the common definition contract, retaining table/board behavior and adding generated calendar/undated-item rendering where supported.
  - Replace incident-template-key dashboard selection with configured projections that work under independent workflow, role, section and stage keys.
  - Derive counts, labels, urgency announcements and available filters only from authorized data. Named confidential assignments remain authoritative, and administration still grants no implicit support-note access.
  - Keep UI rendering separate from context queries and policy decisions. Implement database-level authorized filtering/pagination and batched projections for the new/migrated surfaces here; neither paging unauthorized rows then filtering nor a load-all wrapper is acceptable. S11-T02 completes remaining legacy paths and scale measurement before larger-volume readiness is claimed.
  - Add query-count/batch and result-bound checks with multiple pinned versions and uneven accessible/hidden records. Define whether totals are pre-filter or post-filter, use deterministic tie-breaking, and validate filter/sort/column/calendar references against their types and authorized projections. Hidden fields must not influence visible ordering, counts or filter choices. Keep date-only fields separate from timezone-rendered instants.

- [ ] S10-T03 Expose finance setup and summaries as reusable capability surfaces.
  - Replace inferred correction resets (such as clearing every non-money section on finance release) with explicit validated invalidation/reset declarations. Preserve legacy semantics only for pinned legacy versions. Test approval invalidation and release while unrelated operational/confidential sections survive, including rollback if a later effect fails.
  - Define bounded reset targets and approval invalidation semantics before wiring the editor. Reject unknown targets and invalid combinations, audit affected state without leaking cleared content, and advance the affected revisions in the same transaction as reservation release and stage change. Test stale saves against a reset, duplicate replay, an unrelated section surviving and failure after an earlier effect. Do not introduce arbitrary expressions or a second transition engine.
  - Add schema/editor-configurable finance account binding/setup and authorized reservation/spend/balance surfaces using the existing Finance context and additive capability registry.
  - Distinguish organization-owned accounts from process definitions and bound process views; shared accounts across requisition/trip copies must retain transactional protection and scoped visibility.
  - Define authority for account creation/allocation separately from workflow publication and ordinary finance viewing. A declared finance block must not grant account administration. Specify whether each summary is a process projection or an explicitly authorized shared-account total; process access alone must not reveal another process's transaction details. New mappings/publications must not redirect existing records' pinned account.
  - Preserve separate allocation, reservation, posting and reversal authority, prohibited self-approval, partial receipt guards, idempotency and audit. A configured UI block cannot bypass these commands.
  - Verify composition with ordinary record and resource/item blocks, including invalid graph/actor/binding rejection. Do not invent payment-provider, tax, multi-currency or full accounting behavior.

- [ ] S10-T04 Generalize curated communications and verify copied school processes.
  - Model curated release explicitly: an authorized internal actor may release declared content to a verified recipient without giving that recipient internal record/section access. Define permitted source fields, release authority, recipient relationship and recipient-visible status/history; do not copy every field readable by the sender. Named confidential support notes are never included implicitly.
  - Specify content/recipient snapshot and version semantics at enqueue, then revalidate current organization, recipient relationship and release eligibility at dispatch/retry/result application. Revoked or suspended recipients must not receive queued content; changed source data must not silently alter an already authorized message. Exercise revocation between enqueue and dispatch, duplicate attempts, failed/ambiguous simulation and closure guards. Reuse the existing durable outbox protocol.
  - Declare supported participant recipients, curated content projections and delivery-status/closure guards without school-specific keys. Confidential internal sections must never be copied implicitly into a message.
  - Reuse the durable outbox, scoped eligibility checks, explicit simulation labels, bounded retries and ambiguous-outcome handling. Use simulated adapters here; real access-message transport belongs to S12-T03 and required workflow integrations to S13-T03.
  - Recreate enrollment, incidents, requisition and field-trip definitions under independent keys through editor/import, local mappings and publication. Exercise external/ordinary/restricted roles, corrections, finance, assignments and communication failure/retry through generated pages.
  - For each example, map the supported behaviors in design/06-school-templates.md to its definition, generated route and named acceptance scenario. Incident recipients receive only the curated release, not the internal incident record. Extend the blank equipment service desk with the same participant/view/communication contracts, rather than introducing another domain screen. Fixtures may use supported scoped commands; user-facing setup and publication must also have interaction coverage.
  - Record unsupported combinations explicitly. Update authoring/operating documentation and run mix precommit, asset build and focused LiveView/capability/privacy checks with evidence.

## Acceptance criteria

- The first participant vertical slice has recorded setup, route, privacy, revocation and publication evidence before broader feature expansion. All corrected Sprint 09 acceptance tests remain green; no new generic path depends on an example implementation.
- Each new/migrated collection surface performs bounded authorized reads with documented filter/count/order semantics and regression checks. Full customer-volume performance remains Sprint 11; unbounded implementation of the new surfaces cannot be deferred there.
- Curated delivery grants only the explicitly released projection, and queued/retried work revalidates live recipient eligibility. A recipient without internal record access can receive authorized curated content while internal notes and unrelated metadata remain inaccessible.

- Generated experiences use the shared capability execution and query contracts. Correction/reset policy is explicit; combined capability execution cannot partially commit or erase unrelated data. Account rebinding and new publications leave existing records' business semantics pinned while honoring current revocation.
- Each school recreation and the equipment service desk fixture has supported setup steps and generated-route assertions in the shared evidence matrix. Core-only processes remain usable without participant, finance or operations setup. User-facing authoring/mapping controls are exercised alongside context tests.

- The four school examples can be installed under new keys with renamed fields/stages and complete their supported staff/external experiences through generated URLs and configuration, without adding a new screen module or route per process.
- An unrelated organization has only its installed processes; example installation remains explicit and never happens during runtime page loads.
- Participant pages, configured dashboards, counts, calendar entries, files, history and messages respect the same field/section/relationship policies, including revocation and differently privileged shared identities.
- Finance setup/read models and curated communications are reusable declared capabilities, while existing budget, confidential-assignment, audit and delivery guards remain authoritative under concurrency.
- Clone/import/export/publication preserves the new supported declarations and pinned versions, excludes local relationships/grants/records and rejects executable or unknown behavior.
- Legacy adapters remain only documented compatibility paths. Full data-preservation, scale and end-to-end replacement acceptance belong to S11-T05; no production notification or customer readiness is inferred here.

## Progress

Actual start / finish: not started / not finished  
Tasks: 0/4. Status: Planned. Existing generated staff pages and capability tests are baseline evidence only.  
Planning date: 2026-10-21. Record dated evidence and remaining defects before changing status.  
Priority: architecture prerequisite before pilot onboarding. Handoff: common participant/view/finance/communication surfaces for Sprint 11 acceptance.

Pre-execution review: 2026-10-22. Sequencing, corrected Sprint 09 invariants, bounded read ownership, curated release semantics and incremental acceptance were clarified under D-29. No task has been started or completed by this planning revision.
