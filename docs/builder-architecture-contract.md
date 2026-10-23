# Builder architecture contract

Reviewed 2026-10-21. This is the acceptance contract for Sprints 09–11. Sprint 09
has [completion evidence](participants-and-documents.md); Sprint 10 is complete with
the [bounded query checkpoint](bounded-projections.md), reviewed
[participant correction/document slice](participant-pages.md),
[configured views/finance](configured-views-and-finance.md) and
[curated communications/recreation evidence](sprint10-generated-experiences.md).
Sprint 11 remains pending.

## Review outcome

The existing sprints cover the missing school and restaurant capabilities, but feature coverage alone does not establish a maintainable builder. Ownership, execution composition, publication validation and recreation evidence must be established before new capabilities, not deferred to final cleanup. The product remains a modular monolith with bounded registered behavior and sequential stages; arbitrary application generation, parallel joins and cross-process orchestration remain out of scope.

Observed implementation gaps at planning (the first Sprint 09 increment is recorded
in [execution contracts and evidence](builder-execution.md)):

- `WorkflowRuntime.Policy.actor?/4`, `discover?/3` and runtime refresh paths still specialize parent/guardian behavior through Enrollment. A renamed process is insufficient evidence that its policies are reusable.
- `PrivateDocuments.allowed?/6` recognizes the application/document field pair. Document semantics must come from a pinned declaration and verified relationship.
- `WorkflowRuntime.transition` coordinates operations, files, calculations and finance directly and clears non-money sections on a finance release back to the initial stage. That inferred reset policy is not a reusable correction contract: unrelated capability data could be cleared.
- `WorkflowRuntime.search/2` loads accessible tickets before filtering and pagination. New generated views need a bounded query contract before they proliferate.
- Capabilities currently declares membership in core/finance/operations; Interface declares blocks. Neither alone specifies transaction ordering, binding lifetime or compatibility between effects.

These observations supplement the [modularity review](modularity-review.md). Existing school and restaurant tests establish regression baselines, not completion of the new contract.

## Ownership and dependency rules

| Boundary | Owns | Must not own |
|---|---|---|
| Catalog contracts | Pure definition validation, vocabulary, graph/reference checks, portable format and version compatibility | Tenant queries, grants, mutations or example-key dispatch |
| Local installation/bindings | Authorized role, participant-directory and account mappings; setup readiness | Local IDs embedded in exported definitions or implicit access grants |
| Runtime coordinator | Pinned definition, command/revision/receipt lifecycle, ordered atomic capability execution, audit/outbox intent | School or restaurant policy, arbitrary template code, provider calls under locks |
| Participant and access services | Verified scoped relationships and current authorization for records, projections, commands and files | Authority inferred from labels, administrator status or broad external roles |
| Capability contexts | Their owned state, bounded validation/commands/projections and business invariants | Direct writes to another capability's tables or a second transition engine |
| Query/projection services | Bounded authorized selection, counts and field projection using pinned versions | Loading all records to paginate or exposing confidential query metadata |
| LiveViews/components | Forms, navigation, conflict/draft state and rendering authorized projections | Database access in reusable components or authoritative business decisions |
| Examples/legacy adapters | Example data and explicit historical mappings into supported services | Dependencies from ordinary generic paths back into example implementations |

Use existing contexts where they satisfy these responsibilities. A new module is justified by owned behavior, not line count. Runtime may invoke a closed capability dispatcher; capability contexts must not recursively invoke the public runtime command to finish the same transition. Extract a shared transaction-level operation where needed. Add dependency checks for forbidden example-module calls in the migrated generic paths, with an explicit, shrinking legacy allowlist and outcome tests.

## Capability execution contract

For each capability record its identifier/version, owning context and tables, dependencies/conflicts, declaration fields, symbolic bindings, guards, effects, authorized projections, commands/errors and migration policy. Keep editor, JSON schema, import, publication and runtime validators synchronized through shared metadata where practical and contract tests otherwise. Do not create a plugin loader or generic callback framework without a concrete need.

Every composed command follows one documented protocol: authorize current scope and target; acquire authorization/business locks in a shared order; resolve the ticket's pinned contracts; validate revisions, inputs and all participating guards; apply ordered effects atomically; write audit, durable receipt and outbox intent; commit; refresh authorized clients. A failed later effect rolls back every earlier effect. Duplicate replay rechecks current access and cannot reapply effects. Asynchronous results recheck authorization and version/input fences. External work runs outside locks.

Declare correction invalidation/reset targets explicitly and validate them against the definition. Do not infer which sections to erase from field types or destination labels. Preserve old published behavior through a version-aware legacy adapter; do not rewrite immutable JSON. Test correction with unrelated operational and confidential sections present, approval invalidation, reservation release and failed-transition rollback.

## Publication and binding lifecycle

Separate portable definition, organization-owned installation bindings and runtime records. Specify which configuration is pinned (business rules, selected account, interface and operational settings) and which remains live (membership/relationship validity, grants, suspension). Pinning never preserves revoked authority. Old records must not silently switch accounts, currencies, reset rules or closing transitions when a new version is published.

Before publication, validate referential integrity, reachable initial/terminal paths, capability prerequisites, correction targets, field types, authorized projection references and required local mappings. Report actionable errors with definition paths in the editor and importer. Static validation cannot prove every business path executable; pair it with synthetic scenario execution. Missing/revoked/archived bindings fail closed with a recoverable setup state; never silently choose an account or participant. Define draft preview, initial installation, rebind, republish and old-version behavior explicitly.

Mixed-version lists use each record's pinned policies and semantics. A process's current navigation may change without breaking direct links to older records. Test renamed/removed stages, fields, pages and capability settings across publications; historical labels and sensitive values must not be resolved from an unrelated current version.

## Incremental recreation evidence

Build executable acceptance scenarios in Sprint 09 and extend them each sprint. Setup uses supported editor/import and scoped context commands, never direct insertion of business rows. Database fixture utilities remain acceptable for low-level isolation tests. Final acceptance also exercises the user-facing authoring and local-mapping controls; a context-only test does not establish usable builder recreation.

| Scenario | Required evidence | Owner |
|---|---|---|
| Enrollment and external correction | Two unrelated participants, verified relationship, reference selection, renamed file fields, correction/release, denied cross-access | S09-T04 then S10-T01/T04 |
| Confidential incident | Named assignment, independent restricted sections, urgency view, curated communication without internal notes | S10-T02/T04 |
| Purchasing and field trip | Shared budget contention, partial receipt, approval invalidation, correction and simulated delivery failure/retry | S10-T03/T04 |
| Restaurant | Menu/resources, captured prices, two destination batches, settlement rollback, table reuse, dated totals | S11-T01/T05 |
| Equipment service desk | External request/correction and attachment, assigned service counter, catalog parts with estimated consumption, handoff and supported settlement | S09-T04, S10-T04, S11-T05 |
| Mixed capabilities and versions | Core-only process, finance-only addition, operations-only addition and combined process; independent publication changes, late-effect rollback and duplicate replay | S09-T05, S11-T03/T05 |

The equipment service desk is a synthetic acceptance fixture, not a new customer commitment. It combines participant and resource/item behavior with independently chosen roles, fields, stages and pages. It does not imply rental returns, deposits, stock accounting or new payment semantics. Configure it from a blank definition as well as exercising copied examples; label changes alone are not sufficient proof.

For each scenario record definition/fixture paths, supported setup steps, assertions, generated routes, legacy dependencies (if any), environment/revision and evidence. Run two process copies and two organizations, including a shared identity with different grants. Keep negative, concurrency, revocation, pinned-version and populated migration checks. Each sprint updates this matrix with actual results and explicit remaining gaps; no success is inferred from a total test count.

## Completion boundary

Sprint 11's D-32 mid-sprint policy qualifies legacy-preservation requirements in
this contract. Permanent version pinning for supported builder definitions is
distinct from executing the retiring application's behavior. Inventory actual
consumers before retaining adapters: remove synthetic-only paths, retain history
through export/snapshots/read-only access where sufficient, and narrowly support
active workflows until migration or drain. Unknown consumers require evidence,
not assumptions. No new definition may depend on retired behavior. Preserve
data integrity and supported mixed-version/revocation tests; populated recovery
does not require reactivating every old write API. See the
[Sprint 11 disposition gate](../sprint_plan/sprint_11.md#mid-sprint-compatibility-policy--d-32).

Sprint 09 establishes contracts and a participant/document vertical slice. Sprint 10 adds generated experiences using that protocol and bounded query interface. Sprint 11 completes performance measurement, operational generalization, legacy replacement and full recreation/preservation. Every new capability ships its own cohesive boundary and tests; S11 extraction is residual cleanup, not permission to accumulate domain coupling. Pilot activation remains governed by Sprints 12–14.
