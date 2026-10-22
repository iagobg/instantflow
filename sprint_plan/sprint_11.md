# Sprint 11 — Cross-domain contracts, scalable reads and builder acceptance

[Sprint index](sprint_index.md) · [Shared roadmap](first_customer_roadmap.md) · Status: Planned · Dependencies: Sprints 09–10; existing restaurant increment; D-09, D-14, D-25–27

Goal: verify that the same maintained builder recreates the original school projects, restaurant service and an independently configured non-school process, with explicit operational contracts and bounded authorized reads. Completion is the architecture gate for pilot work in Sprint 12; it is not customer launch readiness.

Specification: [modularity review and extension rules](../docs/modularity-review.md), [process composition](../docs/process-composition.md), [verification](../design/07-verification.md) and [restaurant scope](../docs/restaurant-pilot.md).

## Tasks

This sprint completes and verifies the [builder architecture contract](../docs/builder-architecture-contract.md) introduced in S09-T05. Ownership and execution boundaries are prerequisites, not work deferred entirely to T03/T04. Preserve task IDs; run T01/T03 compatibility checks before the final T02 scale measurements and T05 acceptance.

- [ ] S11-T01 Make operational assumptions explicit and reusable.
  - Define versioned process contracts for the responsible participant/actor, settlement, reporting timezone, currency and supported payment methods. Keep common labels, schemas, commands and reports aligned; terminology alone must not imply new business semantics.
  - Use organization timezone consistently for default operational dates and instant display/report boundaries while keeping explicit business dates separate. Verify midnight/day-boundary behavior across two configured timezones.
  - Replace restaurant-specific command/API terminology with a generic actor contract using a documented compatibility mapping for Session.waiter and existing payloads. Generate forward migrations through Mix only if stored-model changes are necessary; preserve captured names, prices, receipts and old commands/version pins.
  - Make the current BRL/cash/card/Pix boundary an explicit validated supported contract, or add another option only with its full accounting/reporting rules and tests. Reject unsupported currencies, payment semantics and combinations. Rental deposits, refunds, ingredients, losses and stock balances remain deferred until their own reusable contracts are justified; product-unit consumption remains visibly estimated.

- [ ] S11-T02 Move filtering and pagination into bounded authorized read models.
  - Reuse and measure the bounded query/projection service delivered for Sprint 10 surfaces. Inventory remaining legacy callers; replace any remaining load-all-then-filter behavior in WorkflowRuntime.search and per-record version/section lookups in Views.search with that shared service. Do not defer bounded implementation of Sprint 10's new/migrated surfaces to this task or create a competing query engine.
  - Preserve tenant RLS, process scope, each record's pinned field permissions and exact authorized count/filter semantics. Do not page raw unauthorized data and filter afterwards, or leak hidden rows through totals, sort order or calendar metadata.
  - Use deterministic ordering and explicit query/page limits for table, board, calendar, participant and operational surfaces. Avoid loading record projections for pages that do not declare them.
  - Measure representative and uneven tenant/process volumes, query counts, memory and browser-visible latency on documented synthetic infrastructure. Apply the existing scale targets or record a justified revised acceptance target before implementation; actual customer-host capacity is rechecked in S14-T01.

- [ ] S11-T03 Stabilize capability, authoring and compatibility contracts.
  - Complete the capability descriptors and publication checks introduced in S09-T05: dependencies/conflicts, graph reachability, effect/reset targets, typed projection references, local binding readiness and version support. Report path-specific diagnostics consistently through editor/import. Test ordinary definitions with no optional capabilities and all supported combinations.
  - Verify one ordered transaction across composed effects with failure injected after an earlier effect; assert complete rollback of state, finance, operations, receipts and outbox intent. Verify replay after revocation and asynchronous stale-result rejection. No capability may recursively start a second runtime transition for the same command.
  - Exercise mixed-version lists and direct links after stages, fields, pages, accounts and operational settings change. Use pinned labels/policies and preserve old closing/reset behavior without granting revoked authority. Missing or archived local bindings must produce an actionable, fail-closed setup state.
  - Keep the closed capability/block registries, portable schema, editor, importer and runtime validators synchronized. Add contract checks for field/reference/projection/effect vocabularies, invalid combinations and schema-version compatibility.
  - Verify additive capabilities under independently named processes, allowed local mappings and pinned versions, including finance/resource-session settlement rollback and stale/duplicate command behavior.
  - Define supported legacy URL/data adapters, migration mappings and retirement criteria. Remove process-key dispatch from ordinary generated paths; keep old published records usable without rewriting immutable JSON or erasing historical behavior.
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
  - Rehearse populated migration/backup restoration with original rows, relationships, attachments, audit, operational lines/receipts and pending jobs preserved. Verify legacy URLs and duplicate command replay, cross-tenant/process denial and independent-connection concurrency regressions.
  - Run mix precommit, asset build and relevant runner/deployment checks when affected. Record revision, environment, load/browser/migration evidence and remaining defects; update the review's buildability matrix, decision register, authoring/runbooks and sprint index.
  - Keep durable unsent draft recovery in S13-T02 and physical Windows/POS-80 acceptance in S13-T03; synthetic builder acceptance does not close those reliability or launch gates.

## Acceptance criteria

- Dependency checks enforce the documented module boundaries, with explicit compatibility exceptions only. The processor uses one scoped, version-aware transaction protocol; late failures, duplicate commands and revoked actors cannot produce partial or repeated effects. Examples remain data/adapters rather than core dependencies.

- An empty organization can reproduce the original supported school experiences, restaurant process and an additional non-school process using definitions and local mappings, without new domain-specific routes/screens or developer database edits.
- Roles, relationship policies, file fields, stages, transitions, generated views and communications continue to work when independently named; no hidden example key is required. All privacy, finance and concurrency regression gates still pass.
- The operational actor, timezone, settlement, currency/payment and consumption limits are explicit, validated and preserved across publication versions. Existing restaurant data and supported legacy commands remain usable.
- Authorized filtering/pagination/counts execute within documented query/memory bounds and meet recorded scale targets without revealing protected rows or starving another tenant.
- Portable contracts, editor controls and runtime behavior agree; unsupported fields/capabilities are rejected or clearly unavailable rather than silently broken. The directory_reference acceptance from Sprint 09 remains part of the end-to-end gate.
- Populated migration/recovery and legacy compatibility evidence passes without destructive resets or rewriting pinned definitions. No unresolved modularity, data-isolation or data-loss defect blocks the claimed recreation scope.
- Documentation states delivered and deferred behavior accurately. Sprints 12–14 and the customer activation checklist remain required before real use; Sprint 15 remains post-launch observation only.

## Progress

Actual start / finish: not started / not finished  
Tasks: 0/5. Status: Planned. The 190-test structural-review result is historical baseline evidence, not completion of this gate.  
Planning date: 2026-10-21. Record dated evidence and remaining defects before changing status.  
Priority: architecture gate before pilot engineering. Handoff: verified reusable builder foundation for Sprint 12, with operational reliability and real-customer acceptance still open.
