# Verification and delivery

[Design index](index.md)

## Release gates

1. Four templates complete happy paths and relevant corrections/rejections.
2. Administrator creates a custom workflow without code and imports/exports a definition.
3. Parent enrollment never exposes another family's data.
4. Same-section conflicts preserve drafts; independent sections save; live views converge.
5. Competing approvals cannot double-transition or overspend.
6. Simulated results remain visibly labeled.
7. Mutations have attributable history without confidential-text leaks.
8. User-visible strings, errors, accessibility labels, and demo content are PT-BR.
9. Export/import preserves supported semantics while excluding operational data and grants.
10. Multiple organizations are isolated across identity, database reads/writes, live updates, jobs, files, imports, and metrics; a shared user receives only local roles.
11. Migration from Sprints 00/01 preserves existing data/history and establishes tenant constraints/RLS without resetting the application.

## Test strategy

Unit tests cover guards, policies, and definition validation. Database tests cover constraints/transactions. LiveView tests cover events/visibility. Browser tests cover multiple sessions, mobile, reconnect, and focus.

Concurrency tests use independent database connections, overlapping transactions, and deterministic barriers. Shared sandbox connections do not prove race safety. Required races: same/different sections, two transitions, save/approval, budgets across templates, duplicate commands, and revocation/mutation. Assert rows, balances, receipts, events, and outbox, not just UI text.

Inject crash after commit before broadcast, duplicate/out-of-order events, worker retry, lost acknowledgement, and simulated delivery failure. Verify reconciliation and no duplicate business effects.

Security tests span roles, relationships, stages, and sections: forged events, direct IDs, counts, search, files, history, editor previews, import role mapping, and event payloads. Malformed imports cover duplicate keys, oversized/deep content, unsupported versions, unknown actions, forbidden grants, and executable content.

Add organization as the outer dimension of that matrix. Use two tenants with overlapping names and differently privileged shared identities. Exercise wrong-tenant IDs, cross-tenant associations, receipt collisions, local/global revocation, suspension, two-tab switching, late events, worker reuse, and pooled connections after commit/rollback. Run raw-query RLS checks as the actual non-owner runtime role, not just migration credentials. Check missing tenant context fails closed and global control-plane access remains narrow. Future files and Python must extend this suite when their implementations land.

## Proposed performance targets

Confirm D-09 before sign-off: ten organizations with 10,000 tickets and 50 concurrent staff total; p95 accepted command response ≤ 500 ms and committed update visibility ≤ 1 second on a documented environment. Record per-organization results and test uneven load/queue flooding so a busy tenant does not starve another. Missed events reconcile within configured 30 seconds while connected. Record hardware, distribution, payloads, network, quotas, results, and exceptions. These are targets, not guarantees.

## Sprint 11 read budgets fixed before T02 tuning — 2026-10-22

Use the documented WSL workstation baseline in `docs/performance.md`, with no
concurrent build/test run during timing. Retain D-09's 10 organizations, 10,000
total tickets and 50 concurrent staff and the 500 ms command / 1 second update
targets. Read acceptance adds p95 authorized backend selection/projection ≤500 ms,
p95 browser-visible page completion ≤1 second, ≤32 MiB incremental BEAM memory per
in-flight read and ≤4 MiB fetched result payload per request, including catalog,
policy and supporting queries. The normal page remains 25 records. These are
acceptance budgets, not measurements or production guarantees.

Run the same workload cold (fresh application process, record PostgreSQL cache
state) and warm (at least 100 requests after warmup), reporting every tenant and
the maximum, not just aggregate p95. Compare equal ticket distribution with one
tenant owning 70%; maintain 50 concurrent readers and report quiet-tenant latency.
Independently vary published versions per process at 1/10/100, installed processes
per tenant at 1/10/100, hidden:visible ratios at 0:1/9:1/99:1 and selected readable
fields at 1/10/50 using 1 KiB synthetic field values within schema limits. Include
mixed pinned versions and unrelated processes; keep total ticket count explicit.
Do not silently substitute a smaller cross-product after a failure: retain every
run's exact dimensions and justify any revised workload or target in the register.

Record query count, SQL predicate bytes, planning/execution time, catalog rows/bytes,
fetched record/section rows/bytes, policy compilation time, incremental/peak BEAM
memory and browser paint/network timing separately. Authorization counts/metadata
and revocation must still pass. Constant query count or backend-only timing cannot
substitute for supporting-volume or browser evidence. These new dimensions remain
unmeasured at the first operational checkpoint; collect baseline before tuning.

## Delivery

For Sprint 11, D-32 qualifies historical compatibility checks: use the sprint's
consumer/disposition register to select retained legacy URLs and commands.
Synthetic-only legacy tests must transfer their business/security assertions to
supported builder paths before retirement. Keep populated recovery for supported
and retained data, version pinning and revocation coverage; restored history must
not automatically reactivate retired mutations or pending effects. Unknown
consumer classifications block the retirement acceptance gate, not justify
indefinite compatibility or destructive resets.

Document setup, migrations, seeds/reset, adapters, deployment, environment variables, backup and tested restore, limitations, and troubleshooting. No committed secrets. Demonstrate private file handling. Use synthetic data; real student-data deployment needs a separate readiness decision.

Document organization bootstrap/suspension, runtime versus migration DB roles, fair job dispatch, quota configuration, and shared-database recovery. Rehearse whole-database restore separately from any tenant-selective export/restore; do not imply one can safely substitute for the other.

A sprint is Done only with acceptance evidence, passing checks, no blocking defect, and updated progression. Passing tests does not resolve business decisions.

## Modular-builder gate before pilot engineering

Under D-25–27, Sprints 09–11 add a distinct architecture acceptance gate before Sprint 12. Existing school demonstration evidence is preserved; it does not prove editor-only recreation. From an empty synthetic organization, configure the four school workflows, restaurant service and an additional non-school participant/resource process under independent keys through supported editor/import/local-binding interfaces. Exercise their full supported staff/external/restricted experiences, republish while existing records stay pinned, and verify no process-key-selected screen or developer database edit is required.

Participant/reference/document rules, configured projections, finance/communications, explicit operational limits and bounded authorized read models must pass their sprint-specific privacy, migration, concurrency and scale checks. Populated migration/recovery must preserve existing relationships, files, operational snapshots, audit and receipts. Record unresolved scope explicitly; no isolation or data-loss defect can be accepted as a cosmetic limitation. See [Sprint 11](../sprint_plan/sprint_11.md) for the final gate and [roadmap](../sprint_plan/first_customer_roadmap.md) for separate pilot activation and post-launch evaluation requirements.
