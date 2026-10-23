# Sprint 11 — Cross-domain contracts, scalable reads and builder acceptance

[Sprint index](sprint_index.md) · [Shared roadmap](first_customer_roadmap.md) · Status: In progress · Dependencies: corrected Sprints 09–10; existing restaurant increment; D-09, D-14, D-25–30

Goal: verify that the same maintained builder recreates the original school projects, restaurant service and an independently configured non-school process, with explicit operational contracts and bounded authorized reads. Completion is the architecture gate for pilot work in Sprint 12; it is not customer launch readiness.

Specification: [modularity review and extension rules](../docs/modularity-review.md), [process composition](../docs/process-composition.md), [verification](../design/07-verification.md) and [restaurant scope](../docs/restaurant-pilot.md).

## Mid-sprint compatibility policy — D-32

The retiring application is not an indefinite compatibility target. Preserve the
builder's version pinning, current authorization, audit and data integrity; retain
old executable behavior only for an evidenced consumer. This policy supersedes
blanket legacy-preservation wording in earlier plans. The operational checkpoint
already delivered remains valid; its adapters are provisional pending this audit.

Before extending any compatibility path, T03/T04 must maintain a disposition
register identifying the module/API/route/schema fallback, actual callers and
records, evidence source, required behavior, disposition, owner and concrete
removal milestone or measurable condition. Classify each dependency:

- Synthetic fixtures/demo only: recreate the scenario using supported builder
  contracts, migrate its tests and remove obsolete runtime paths in this sprint.
- Historical data requiring retention: prefer export, immutable snapshots or
  read-only access; retained data alone does not require old mutation APIs.
- Active workflows/clients: retain only the minimum adapter until an explicit
  migration or drain completes, with verification of remaining consumers.
- Unknown: record the missing evidence and resolve it before closing T03/T05;
  neither assume production use nor infer that deletion is safe from absent local
  callers. Ask for environment facts only when repository evidence cannot settle it.

Start with guardian/example-specific access and URLs, inferred resets, legacy
list APIs, waiter payloads, no-argument operational dates and missing-contract
defaults. A historical storage column name alone is not grounds for a migration.
No new editor publication or ordinary template installation may create a dependency
on retired behavior; existing pinned compatibility, if needed, must be explicit and
separate from the new-definition validation path.

Tests that exercise obsolete APIs are evidence of test dependencies, not proof of
active customer need. Preserve their business/security assertions through the new
contracts; do not remove substantive coverage merely to obtain a green suite.
Record each removal and test replacements. Kept adapters must be isolated and
covered by tests for their declared consumers; generic recreation must succeed
without invoking them. Versioning supported builder definitions remains permanent.
This revision authorizes planning and code retirement within the above criteria,
not deletion of user data or destructive resets of an existing environment.

## Tasks

The [S09–10 compatibility inventory](../docs/sprint11-legacy-disposition-inventory.md)
makes D-32 actionable within the existing tasks: T03 owns explicit historical
eligibility and new-publication guards; T04 owns retirement of access/document
adapters, guardian synchronization and domain routes; T02 owns the obsolete list
API; T05 proves preservation for the classified retained set. Complete all six
inventory dispositions before closing their tasks. Source-only evidence must not
be presented as proof that deployed consumers do or do not exist.

This sprint completes and verifies the [builder architecture contract](../docs/builder-architecture-contract.md) introduced in S09-T05. Ownership and execution boundaries are prerequisites, not work deferred entirely to T03/T04. Preserve task IDs; run T01/T03 compatibility checks before the final T02 scale measurements and T05 acceptance.

## Execution checkpoints after Sprints 09–10

1. Inventory the implemented contracts, remaining legacy callers and scenario gaps. Treat the corrected Sprint 09 eligibility/access rules and Sprint 10 projection/form regressions as prerequisites. Reuse existing implementations and tests; do not rebuild completed capabilities to satisfy older planning language.
2. Deliver an early T01/T03 restaurant slice under independent keys through supported authoring/mapping and common generated routes: open a resource session, capture an item price, dispatch to two configured destinations, settle and reuse the resource. Demonstrate an injected late settlement failure rolls back all composed effects before expanding the acceptance matrix. Record the portable definition, setup steps and remaining compatibility dependencies at this checkpoint, not only at T05.
3. Run T02's baseline measurements early enough to guide changes, then repeat the agreed workload after the implementation stabilizes. Perform T04 cleanup where responsibilities actually change. T05 closes the full scenario and preservation matrix; the early slice does not substitute for exception, concurrency or migration coverage.

These are execution/evidence checkpoints, not additional permission gates. The [Sprint 10 follow-up review](../docs/sprint10-followup-review.md) accepts its scope; restaurant generalization and full scale/preservation acceptance remain here.

- [x] S11-T01 Make operational assumptions explicit and reusable.
  - Define versioned process contracts for the responsible participant/actor, settlement, reporting timezone, currency and supported payment methods. Keep common labels, schemas, commands and reports aligned; terminology alone must not imply new business semantics.
  - Use organization timezone consistently for default operational dates and instant display/report boundaries while keeping explicit business dates separate. Verify midnight/day-boundary behavior across two configured timezones.
  - Replace restaurant-specific command/API terminology with a generic actor contract. Audit the existing Session.waiter/payload mapping under D-32; retain old payload acceptance only for evidenced consumers. Generate forward migrations through Mix only if stored-model changes are necessary; preserve captured names, prices, receipts and supported version pins. Do not rename historical columns solely for vocabulary consistency.
  - Make the current BRL/cash/card/Pix boundary an explicit validated supported contract, or add another option only with its full accounting/reporting rules and tests. Reject unsupported currencies, payment semantics and combinations. Rental deposits, refunds, ingredients, losses and stock balances remain deferred until their own reusable contracts are justified; product-unit consumption remains visibly estimated.

- [ ] S11-T02 Move filtering and pagination into bounded authorized read models.
  - Reuse and measure the bounded query/projection service already used by WorkflowRuntime.search and WorkflowCatalog.Views. Inventory actual remaining callers, including WorkflowRuntime.list and operational/compatibility surfaces; migrate residual load-all paths or document a bounded compatibility exception with an owner and retirement condition. Preserve the existing service rather than creating a competing query engine.
  - Preserve tenant RLS, process scope, each record's pinned field permissions and exact authorized count/filter semantics. Do not page raw unauthorized data and filter afterwards, or leak hidden rows through totals, sort order or calendar metadata.
  - Use deterministic ordering and explicit query/page limits for table, board, calendar, participant and operational surfaces. Avoid loading record projections for pages that do not declare them.
  - Measure representative and uneven tenant/process volumes, query counts, memory and browser-visible latency on documented synthetic infrastructure. Apply the existing scale targets or record a justified revised acceptance target before implementation; actual customer-host capacity is rechecked in S14-T01.
  - Vary published-version count, installed-process count, hidden-to-visible record ratio and selected projection width independently of ticket count. Measure catalog loading/policy compilation, SQL predicate size/planning cost, fetched rows/bytes and application memory as well as query count. Constant query count and a 25-record page are not evidence that supporting work is bounded. Include mixed old versions and unrelated processes; any cache must preserve pinned semantics and current revocation.
  - Before tuning, record numeric read-latency/memory budgets and the version/process distributions used alongside D-09's command/update targets in design/07-verification.md. Report per-tenant results and cold/warm runs. Do not silently lower a target or change the workload after seeing a failure; retain the failed result and justify any changed acceptance target.

- [ ] S11-T03 Stabilize capability, authoring and compatibility contracts.
  - Complete the capability descriptors and publication checks introduced in S09-T05: dependencies/conflicts, graph reachability, effect/reset targets, typed projection references, local binding readiness and version support. Report path-specific diagnostics consistently through editor/import. Test ordinary definitions with no optional capabilities and all supported combinations.
  - Verify one ordered transaction across composed effects with failure injected after an earlier effect; assert complete rollback of state, finance, operations, receipts and outbox intent. Verify replay after revocation and asynchronous stale-result rejection. No capability may recursively start a second runtime transition for the same command.
  - Exercise mixed-version lists and direct links after stages, fields, pages, accounts and operational settings change. Use pinned labels/policies and preserve old closing/reset behavior without granting revoked authority. Missing or archived local bindings must produce an actionable, fail-closed setup state.
  - Keep the closed capability/block registries, portable schema, editor, importer and runtime validators synchronized. Add contract checks for field/reference/projection/effect vocabularies, invalid combinations and schema-version compatibility.
  - Maintain a supported-field/surface matrix for ordinary forms, participant forms, views and messages. For each supported combination, exercise editor/import roundtrip and actual rendered form payloads through save/readback: empty and cleared values, multi-select hidden sentinels, typed conversion and invalid values. Unsupported combinations must fail publication or be explicitly unavailable. Reuse FieldValues for shared transport conversion; keep business validation in its existing owner. Do not expand participant directory-reference or message-source support merely to fill the matrix.
  - Check authorization parity across discovery, list/count/filter metadata, detail, direct file URLs, mutation events and delivery entry points. Exercise a selected and an omitted field, subject-only identities, explicit scoped staff grants, current revocation and old-version links. Include multiple participant pages: a direct file may be released by any currently admitted pinned page selecting that exact field, but a non-admitted page cannot release it. Page selection never grants section authority. Preserve curated-message snapshot/recipient semantics rather than treating messages as ordinary internal record access.
  - Verify additive capabilities under independently named processes, allowed local mappings and pinned versions, including finance/resource-session settlement rollback and stale/duplicate command behavior.
  - Complete the D-32 disposition register and retire unneeded legacy URL/data/command paths. For evidenced consumers, define migration, read-only retention or a narrowly scoped drain adapter. Remove process-key dispatch from ordinary generated paths; preserve supported pinned records without silently rewriting immutable JSON. Do not equate retained history with permanent execution support.
  - Keep example content and installation separate from the platform core. Document extension rules and supported/deferred capabilities in the authoring guide and README.

- [ ] S11-T04 Separate remaining editor and command responsibilities where behavior changed.
  - Enforce the context ownership/dependency rules and reviewed legacy allowlist established in Sprint 09. Remove residual example-service dependencies from migrated generic commands, policy, projections and UI; record each remaining compatibility dependency and its retirement condition. T04 is residual integration cleanup; T01–T03 and earlier sprints must already preserve cohesive boundaries.
  - Extract cohesive authoring panels, validation helpers and runtime/context command implementations touched by Sprints 09–11, with explicit inputs and server-authoritative contexts. Keep reusable templates free of queries and mutations.
  - Centralize repeated supported-contract, generated-route, formatting and authorization-projection decisions where an owner is identifiable; avoid moving duplication into pass-through abstractions with no responsibility.
  - Preserve form IDs, keyboard/focus behavior, revision conflicts and unsaved-draft handling. Use meaningful outcome tests around the extracted boundaries rather than tests that mirror private implementation.
  - Retain the modular monolith and bounded registered capabilities. A dynamic plugin framework, arbitrary template code and a rewrite based only on module line counts are outside this sprint.

- [ ] S11-T05 Pass the full builder recreation and preservation gate.
  - Complete the incremental evidence matrix, including the equipment service desk composed from a blank definition, not just renamed examples. Record fixture paths, supported setup actions, generated routes, assertions and remaining adapter dependencies for each scenario. Verify the authoring/local-mapping UI as well as context commands; schema acceptance and a total test count are not sufficient recreation evidence.
  - Start from an empty synthetic organization and use only supported editor/import/local-binding interfaces to recreate all four school examples and the restaurant workflow under independent keys. Configure an additional non-school participant/resource process to show reuse beyond renamed sample labels.
  - Exercise full supported happy/exception paths, external and restricted access, partial receipt/finance guards, kitchen/parrilla destination batches, checkout/table reuse, daily summaries, communication failure/retry and republishing while existing records remain pinned.
  - Rehearse populated migration/backup restoration for supported builder data and the D-32 retained-data set, preserving relationships, attachments, audit, operational snapshots and receipts. Give pending jobs an explicit drain/migrate/cancel disposition with audit; do not blindly replay retired effects. Verify only the legacy URLs/commands justified in the register, plus supported duplicate replay, cross-tenant/process denial and independent-connection concurrency regressions. Recovery of historical data need not reactivate obsolete write routes.
  - Run mix precommit, asset build and relevant runner/deployment checks when affected. Record revision, environment, load/browser/migration evidence and remaining defects; update the review's buildability matrix, decision register, authoring/runbooks and sprint index.
  - Keep durable unsent draft recovery in S13-T02 and physical Windows/POS-80 acceptance in S13-T03; synthetic builder acceptance does not close those reliability or launch gates.

## Acceptance criteria

- Dependency checks enforce the documented module boundaries, with explicit compatibility exceptions only. The processor uses one scoped, version-aware transaction protocol; late failures, duplicate commands and revoked actors cannot produce partial or repeated effects. Examples remain data/adapters rather than core dependencies.

- An empty organization can reproduce the original supported school experiences, restaurant process and an additional non-school process using definitions and local mappings, without new domain-specific routes/screens or developer database edits.
- Roles, relationship policies, file fields, stages, transitions, generated views and communications continue to work when independently named; no hidden example key is required. All privacy, finance and concurrency regression gates still pass.
- The operational actor, timezone, settlement, currency/payment and consumption limits are explicit, validated and preserved across supported publication versions. Retained restaurant data remains readable; legacy mutations remain usable only where the D-32 register requires them.
- Authorized filtering/pagination/counts execute within documented query/memory bounds and meet recorded scale targets without revealing protected rows or starving another tenant.
- Portable contracts, editor controls and runtime behavior agree; unsupported fields/capabilities are rejected or clearly unavailable rather than silently broken. The directory_reference acceptance from Sprint 09 remains part of the end-to-end gate.
- Supported field/surface combinations pass real form-payload roundtrips; direct URLs and forged events cannot bypass the declared release boundary. The maintained Sprint 09 eligibility/access and Sprint 10 document/multiple-choice regressions remain green.
- Read-model evidence includes version/process growth and supporting-query cost, with numeric budgets recorded before tuning. A fixed page size or constant SQL query count alone does not close the scale gate.
- The D-32 register has no unresolved consumer classification: synthetic-only runtime paths are retired, and each retained adapter has evidenced consumers, a bounded responsibility and an owner/removal condition. New definitions cannot enter retired paths; common recreation passes without them. Supported version pinning and current authority remain enforced.
- Populated migration/recovery and justified compatibility evidence passes without destructive resets or rewriting pinned definitions. Archived history does not implicitly preserve executable legacy behavior. No unresolved modularity, data-isolation or data-loss defect blocks the claimed recreation scope.
- Documentation states delivered and deferred behavior accurately. Sprints 12–14 and the customer activation checklist remain required before real use; Sprint 15 remains post-launch observation only.

## Progress

Actual start / finish: 2026-10-22 / not finished  
Tasks: 1/5. Status: In progress. The 190-test structural-review result is historical baseline evidence, not completion of this gate.  
Planning date: 2026-10-21. Record dated evidence and remaining defects before changing status.  
Priority: architecture gate before pilot engineering. Handoff: verified reusable builder foundation for Sprint 12, with operational reliability and real-customer acceptance still open.

Pre-execution revision: 2026-10-22, D-30. Updated the completed-query baseline,
early restaurant checkpoint, public-entry authorization parity, supported-form
matrix and version/process scale dimensions after the corrected Sprint 10 review.
Task IDs, task count and feature scope remain unchanged; no task is started by
this planning revision.

Execution checkpoint — 2026-10-22: T01/T03 started. The
[operational checkpoint](../docs/sprint11-operational-checkpoint.md) records the
portable independent-key restaurant, editor mapping/payment controls, generic
responsible-actor compatibility, organization dates, pinned payment/access rules
and late rollback across operations/runtime/finance/receipts/outbox. It also
inventories the remaining read and compatibility paths. Numeric T02 budgets and
version/process distributions are recorded before read tuning in
[verification](../design/07-verification.md). All five task checkboxes remain open:
scale, complete contract/public-entry matrices, historical page fallback, full
recreation and populated recovery acceptance are still required.

Mid-execution revision — 2026-10-22, D-32: compatibility now requires evidenced
consumers and a disposition/retirement gate. Apply this to the existing operational
checkpoint before extending its adapters. Preserve its work and the five task IDs;
status remains In progress, 0/5. Earlier references to preserving old commands,
URLs and behavior are subject to this policy; supported builder-version fallback
and data integrity remain required.

Retirement checkpoint — 2026-10-22: the owner confirmed all existing environments
are synthetic/demo only, and explicitly approved both shared-policy and remaining
invitation/route retirements. All eight inventory entries now have implemented
dispositions. T01 is complete: explicit operational contracts, captured actor
names, organization dates, pinned payments and atomic settlement are verified;
obsolete payload/default compatibility is removed. The
[retirement checkpoint](../docs/sprint11-retirement-checkpoint.md) records the
replacement coverage, archive fences and populated migration/backup restoration.
T02–T05 remain open for their full acceptance criteria. Status: In progress, 1/5.

Review correction — 2026-10-23: the two reproduced first-checkpoint P2 findings
are addressed with explicit operational archival and pinned-result opening replay.
[Populated operational migration/restore evidence](../docs/sprint11-first-checkpoint-review-resolution.md)
now verifies historical unpaid/paid values, replacement publication, same-process
resource reuse and day closure. This replaces the initial empty-operational-table
limitation for that case; full T05 recreation and other acceptance gates remain
open. Task progress remains 1/5, In progress.
