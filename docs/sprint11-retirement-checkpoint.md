# Sprint 11 retirement checkpoint

The 2026-10-23 [first-checkpoint review corrections](sprint11-first-checkpoint-review-resolution.md)
supersede this checkpoint's initial operational disposition and opening-replay
claim: unpaid sessions/pending batches now receive an audited archive state;
replay checks the result's pinned version; populated operational restore followed
by same-process replacement/resource reuse/day closure is covered.

Executed 2026-10-22 under D-32, continuing the first operational checkpoint on
base revision `71ecf2ef9efc882e468aafbcf2164c53fb4c974a`. The owner's explicit
synthetic-only classification resolves the previous deployment-consumer unknown.
See the [disposition register](sprint11-legacy-disposition-inventory.md) for the
eight classified entries, evidence source, owner and completed removal milestones.

## Result

The runtime no longer infers school authority from omitted optional fields, calls
Enrollment for file decisions, infers correction targets, maintains guardian dual
writes or offers the old school/operation alias screens. Ordinary core-only
definitions honor explicit current staff grants, including grants held by a
historical parent identity. Relationships, assignment eligibility, section policy,
file release and query/detail parity remain server-authoritative. Supported
builder version pinning is permanent; obsolete example execution is retired.

The executable Enrollment and Incidents contexts, three domain LiveViews,
LegacyAccess, LegacyPolicy, LegacyResets and LegacyWorkspaces are removed.
The generic query service replaces the unbounded list API. New commands use the
captured `responsible_actor` name and organization-scoped operational dates. New
publication requires explicit document policies and an operational v1 declaration
with a closing transition. BRL, full manual settlement, cash/card/Pix and estimated
product-unit consumption remain the only supported operational semantics.

`Examples` is an optional data installer into the supported catalog; no runtime,
policy, projection or generated renderer dispatches through it. Modern school
examples, demo seeding, the load harness and delivery/recovery walkthrough use
ordinary declarations and commands. Original school JSON is retained under
`test/fixtures/history/` exclusively for populated historical-schema rehearsals.

## Historical data and jobs

The generated forward migration
`20261022175214_retire_synthetic_legacy_execution.exs` records historical versions
that actually declare guardian scopes, undeclared attachments, inferred financial
resets or missing operational contracts in a tenant-scoped, operator-owned
`retired_workflow_versions` table. Eligibility is trusted provenance outside
user-authored JSON. Runtime can read this table and cannot classify/unclassify
versions. New publication cannot recreate these dependencies.

The migration preserves definitions, tickets, sections, files, source guardian
links, mapped relationships, captured names/prices, audit and receipts. It stops
the synchronization bridge and removes runtime write privileges on its source
tables. Pending/failed/ambiguous deliveries and queued/running calculations for
the classified set are cancelled with organization audit entries; their payloads
and snapshots remain. Supported work is not cancelled. The migration runs in a
maintenance transaction and restores FORCE RLS before becoming visible.

Current permission checks run before exposing retirement errors. Archived command
execution and successful receipt replay are denied. Existing permitted staff can
read history with editing, assignment, transition and retry controls removed;
generated operational sessions display an archive notice and retain captured data.
Curated retry/release, participant commands, file mutations and calculation-result
fences cannot reactivate retired effects. Archived private content is excluded
from automatic expiry purge. Files lacking a supported declared policy are
retained for operator backup/export; no new legacy download permission is inferred.

Historical schema/column names (`Enrollment.Document`, `waiter`,
`legacy_guardian_link_id`) are retained as storage/provenance. Their names do not
restore executable behavior or justify a destructive schema rename.

## Replacement and preservation evidence

| Former dependency/assertions | Maintained replacement |
|---|---|
| Enrollment install/create/invite/verify | `EnrollmentFixtures` composes Examples/catalog publication, generic external invitation, Participants create/verify/revoke and guarded record commands; it creates no new enrollment/guardian source rows |
| Family lifecycle, correction, minimal IT data, provisioning failure/retry/replay | `test/instantflow/enrollment/enrollment_test.exs`; actual participant projection and curated release replace the hand-written public projection |
| Family invitation proof, expiry/reuse, multiple verified identities, unrelated/cross-tenant IDs, safe invalidations | Same context suite and `identity_test.exs`, preserving denial, current revocation and metadata assertions |
| Old private-file behavior | `enrollment/documents_test.exs`, declared-policy tests and generated family-page tests preserve spoofed bytes, path checks, bounds, quarantine, independent review, rejection/deletion/expiry and cross-record/field denial |
| Old portal and route-local draft state | `enrollment_live_test.exs` uses generated field/upload/action forms, verifies record navigation remounts without previous values, revocation removes controls, and direct downloads retain private headers and current relationship checks |
| Incident triage, separate counselor/dean sections and confined uploads | Configured urgency views and generated process/record pages in `incidents_live_test.exs`; declared document review now requires an independent currently assigned counselor |
| Budget allocation convergence, current revocation and forged commands | Generated finance_setup/finance_summary blocks in `budgets_live_test.exs`; calendar and assignment checks retain the shared projection engine |
| Real connection races and RLS | `runtime_role_test.exs` retains overlapping family saves, one winning revision, explicit participant revocation before a queued save, counselor assignment races and tenant ownership assertions |
| Historical populated migration/restore | `guardian_migration_test.exs` seeds the actual old JSON with the operator repository, migrates two organizations/four mappings/two files and pending refresh intents, then pg_dump/pg_restore compares retained tables and retirement classification; obsolete work stays cancelled, runtime guardian writes fail and expired archived bytes survive purge |
| Retired reachability and archive UI | `retired_routes_test.exs`, `retirement_publication_test.exs`, `archived_record_live_test.exs` assert 404s, absent modules/APIs, fail-closed publication, no old invitation side effects, read-only historical controls and retirement-aware replay |

The old counselor self-review expectation was replaced with the supported declared
policy: self-review is denied, independent assignment/review succeeds, returning
the assignment restores authorized access, and later revocation removes it. This
retains lifecycle/privacy coverage while removing the implicit legacy privilege.

## Operator runbook and remaining gates

Before applying the migration to any existing environment, take and verify a
private whole-database backup using the existing deployment runbook. Use a
maintenance window; no mixed-schema rolling operation is supported. Review the
retirement table and `legacy_execution_retired`, `retired_delivery_cancelled` and
`retired_calculation_cancelled` audit entries. Do not requeue cancelled historical
jobs or grant runtime writes back to source guardian tables.

For synthetic demos, publish a current supported definition as a new version or
an independent process, then use generic invitations and explicit verification.
The updated seed uses separate command keys and retains old records. Never edit
immutable JSON or transfer old receipts onto a different command. Historical
backup/export is an operator operation; recovery does not re-enable old routes.

The seed publishes current enrollment, incident, requisition and trip examples
only when absent or when the latest version is classified retired. Supported
customizations stay in place. An isolated clone seeded twice preserved all old
enrollment/guardian source rows, kept the second run's version/ticket/relationship
counts unchanged and left all four examples on valid, unretired latest versions.

## Validation — 2026-10-22

The full `mix precommit` gate passes 287 tests, including actual runtime-role
concurrency, archived access, invitation denial, route 404s and populated migration
recovery. Assets build successfully. A runner smoke test uses a newly created
10,000-record/10-organization database and 50 staff: all 50 guarded saves succeed.
This verifies the migrated harness; its one-iteration timings do not close T02's
expanded scale workload.

One repeat (seed 403697) returned a same-URL LiveView reload during the copied
trip recreation. The same file/seed then passed all four tests. The failed log
is preserved, and a full same-seed repeat includes read-only session/mount error
tracing. No retry or relaxed assertion was added to the tests. The intermittent
failure's cause is not established; it remains an observation for the open T05
acceptance gate rather than a claimed product fix.

The separate delivery/recovery walkthrough clones the serving database from a
read-only backup, migrates the clone, installs current supported publications and
exercises participant enrollment, communications/retry/replay, requisition guards,
trip prerequisites, independent incident review and a fifth imported definition.
All table snapshots match after whole-database restore, private bytes download,
absent runtime context denies rows, and attempted migration rollback is refused
without changing data. The populated clone includes eight retired versions,
four retained enrollment rows/four guardian source links, five relationships,
two private files, 62 receipts and operational tables. Those operational tables
are empty in this recovery fixture; populated operational restore remains part
of the wider T05 gate. Only disposable databases were migrated or written.

Machine-readable [recovery](evidence/sprint11-retirement-recovery.json),
[seed](evidence/sprint11-retirement-seed.json) and
[harness smoke](evidence/sprint11-retirement-harness-smoke.json) reports retain
row hashes and limitations. These local synthetic
checks do not establish tenant-selective recovery, off-host/encrypted backups,
production recovery objectives or browser latency.

The compatibility inventory is resolved. T01's operational contract is delivered;
the wider T02 read/scale measurements, T03 capability/form/public-entry matrix,
T04 residual cohesion and T05 full builder recreation/preservation matrix are
still required. This checkpoint does not claim browser latency, new scale
measurements, production deployment, real customer use or physical printer
acceptance. Validation/source hashes are recorded in
[retirement evidence](evidence/sprint11-retirement-checkpoint.json).
