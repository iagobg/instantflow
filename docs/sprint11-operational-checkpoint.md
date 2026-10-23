# Sprint 11 operational checkpoint

Historical first-increment report. Its provisional compatibility adapters were
subsequently retired under D-32; current behavior and validation are recorded in
the [retirement checkpoint](sprint11-retirement-checkpoint.md). The original
checkpoint evidence remains a dated snapshot rather than current API guidance.

Started 2026-10-22 on base revision `71ecf2ef9efc882e468aafbcf2164c53fb4c974a`,
with the existing D-30 planning and Sprint 10 follow-up review changes preserved.
This is the first T01/T03 increment. Sprint 11 remains In progress, 0/5 tasks
complete. It does not close the full recreation, scale or preservation gate.

## Delivered contract

`WorkflowCatalog.OperationalContract` owns the pure v1 declaration at
`interface.operations`. The portable schema, editor, publisher and runtime agree:
captured responsible name, full manual settlement, organization reporting timezone,
BRL integer cents, a nonempty subset of cash/card/Pix and estimated product-unit
consumption. Other versions, currencies, settlement/payment semantics and stock
accounting fail validation. The editor's page panel exposes payment selection and
states the fixed semantics. No additional capabilities or dependencies were added.

New commands use `responsible_actor`. Historical `waiter` payloads and the
`service_sessions.waiter` / `fulfillment_batches.waiter` columns remain compatible;
`Operations.actor_name/1` provides the generic read vocabulary. Conflicting old/new
names are rejected. Receipts retain the exact original payload digest: changing
payload spelling while reusing a key is still an idempotency mismatch. No migration
or immutable-definition rewrite is needed. Captured names, prices and lines remain
unchanged. Retire the payload adapter only after historical clients no longer use
it; stored-column renaming requires its own preserving migration.

Session and batch commands, direct visit access and replay now select the ticket's
pinned version before checking current grants. Payment options and responsible
labels on a generated visit use that same version. New sessions/catalog setup use
the current publication. A new cash-only publication cannot remove Pix from an
existing session, and revoked grants cannot replay its settlement receipt.

Organization timezone controls default dates and batch/print/day-close instant
display. The contract deliberately selects the organization's current timezone;
it does not embed a timezone or local identifier in portable definitions. Explicit
business dates remain stored dates and are not shifted on settlement. The no-argument
`Operations.today/0` is retained as a São Paulo compatibility API; generated pages
use `today/1`, which refreshes organization settings under tenant authorization.

## Executable evidence matrix

| Scenario | Setup and generated interface | Assertions |
|---|---|---|
| Independent restaurant | `test/fixtures/sprint11/supper_room.json`; `Templates.import`, mapping/save/publish; symbolic role `host`, binding `service_team`, stages `serving`/`paid`, transition `complete_visit`, page `service_desk` | Catalog/resource setup, captured responsible name and prices, Cozinha/Parrilla batches, explicit handoff, settlement, resource reuse, dated sales and duplicate receipt replay |
| Editor/local mapping | `test/instantflow_web/live/sprint11_operational_authoring_test.exs`; `#template-mappings`, `#interface-page-form`, publication, `/o/:slug/processos/:workflow_id/p/service_desk` | Real editor payment-select payload persists, generated opening uses `responsible_actor`, settlement offers only configured cash and succeeds |
| Late settlement failure | `test/instantflow/sprint11_operational_checkpoint_test.exs`; outbox quota rejects after session/transition effects | Session and stage/sections, audit, both receipt families and outbox roll back; retry succeeds once; grant revocation denies replay |
| Finance composition | Same maintained test; independently keyed `supplies_counter` combines operations with the supported purchasing contract through publication and scoped commands | Reserve/post/receive followed by quota failure during closing preserves session, ticket, sections, account, hold, finance entries, audit, receipts and outbox; successful retry adds exactly one completion entry |
| Version/payment compatibility | Same maintained test; clone/save/publish cash-only settings after opening a session | Old Pix settlement succeeds; new Pix settlement fails; cash succeeds; historical `waiter` payload works and ambiguous actor payload fails |
| Portable contract and dates | `test/instantflow/operational_contract_test.exs`, `test/instantflow/local_time_test.exs` | Import/export roundtrip, legacy default resolution, unsupported semantics rejected, São Paulo/Tokyo midnight boundaries and refreshed organization settings |

The restaurant and editor scenarios install into empty synthetic organizations
using supported interfaces. The composed finance scenario deliberately reuses
existing finance fixtures; it does not establish blank-definition equipment-desk
recreation. LiveView form execution is automated interface evidence, not a browser
paint/network or physical printer measurement.

## Residual inventory and next execution work

Validation on 2026-10-22: `mix precommit` passed (281 tests, zero failures,
seed 926178; compilation with warnings as errors, unused-dependency and format
checks passed). `mix assets.build` and `git diff --check` passed. The focused
operational/finance checkpoint passed three tests, seed 957318. Full-suite logs
retain the existing migration-module redefinition warnings from recovery tests.
No database migration or deployment/runner changes were needed in this increment.

| Boundary | Observed remaining work | Owner / retirement condition |
|---|---|---|
| `WorkflowRuntime.Projections`, `PolicyQuery` | Already bound ticket selection/counts; catalog loading and predicate compilation still grow with published versions | T02: measure and bound supporting work using the pre-tuning budgets in `design/07-verification.md`; preserve the existing engine |
| `WorkflowRuntime.list/1` | Load-all compatibility API; source inventory finds test callers and no production call sites | T02: replace with an explicitly paged API, migrate compatibility tests and document/remove any remaining exception |
| `Operations.workspace`, `visit`, `report!` | Catalog/resources/open sessions/batches and daily report still load lists; report has per-open-session totals | T02: bounded operational selection and SQL aggregates, pinned authorization parity, deterministic pages and volume evidence |
| `Workspaces.latest/installed/get`, participant discovery | Tenant catalog scans and process/version growth are unmeasured | T02: measure cold/warm catalog, policy and discovery costs with unrelated processes and hidden records |
| Old generated operational links | Command-level pinning is covered; removed current pages/capability/access mappings still need full mixed-version discovery/direct-link fallback | T03/T05: removed-page and changed-access acceptance before claiming all historical links preserved |
| Transaction composition | Existing scoped nested Ecto transactions roll back the checkpoint effects; runtime and operations retain their public coordinators | T03/T04: audit lock order and transaction-level ownership across remaining capabilities; no new competing engine introduced |
| Field/surface and public-entry parity | Sprint 09 eligibility/document and corrected Sprint 10 form/release tests remain prerequisites | T03: complete the actual payload matrix and multiple-page file-release cases without expanding deferred fields |
| Full builder/recovery acceptance | All four school examples, blank equipment service desk, exceptions, cross-tenant/process denial, independent-connection races and populated backup/restore need final evidence | T05: incremental matrix and preservation rehearsal, not just the suite total |

No scale target, browser timing, populated restoration, deployment or customer
acceptance is claimed by this checkpoint. The existing original-school and legacy
adapter evidence is retained. Sprints 12–14 and physical Windows/POS-80 acceptance
remain separate gates. Validation and source hashes are recorded in
[checkpoint evidence](evidence/sprint11-operational-checkpoint.json).
