# PostgreSQL efficiency improvement plan

Prepared 2026-11-06 against application commit `10cb39783293765a858b6f342cf4803773048423`.
Status: implementation in progress. The completed increments and remaining acceptance work are recorded below. The targets remain unchanged.

Reduce the database work required for an authorized interaction while retaining InstantFlow's configurable workflows, organization isolation, safe concurrent editing, and durable live updates. Start with repeated transaction setup, unnecessary reads, and background work. Keep PostgreSQL authoritative and retain the modular monolith and closed capability registry.

The governing contracts are [product scope](../design/01-product.md), [architecture](../design/02-architecture.md), [concurrency and live UX](../design/05-concurrency-ux.md), [verification budgets](../design/07-verification.md), and the [builder architecture contract](builder-architecture-contract.md). This plan supplements the completed architecture work and should precede broader pilot load. It does not reopen completed sprints or mark customer activation gates complete.

## Evidence and priorities

[Sanitized diagnostic evidence](evidence/db-efficiency-diagnostics-2026-11-06.json) combines the local review with fresh measurements from the running [benchmark instance](https://instantflow-benchmark.iagobussoletti.com.br). Both use the reviewed application revision.

| Observation | Measured result | Implication |
| --- | --- | --- |
| Local record open, HTTP plus connected LiveView | 412 SQL statements | Repeated authorization and projection work dominates statement volume |
| Local idle record heartbeat | 153 statements | An open tab performs substantial work without a business change |
| Local transition reason edit | 29 statements | Navigation and scope reloads occur even for a small form event |
| Local save with editing presence | Approximately 370 statements | Measure the initiating event and subsequent presence/outbox refreshes together |
| Local empty dispatcher pass | 31 statements for one organization; 301 for ten | Background cost grows with all active organizations |
| Hosted idle worker, 20 seconds | 2,356 statements, 76 passes, 228 transactions | Approximately 118 statements/second with no pending outbox work |
| Hosted authorized detail read, 20 samples | 31 statements/read; median 11.06 ms, range 10.27–16.02 ms | Individual reads are quick on the small dataset, but composing them repeatedly is costly |
| Hosted navigation read, 20 samples | 14 statements/read; median 5.98 ms | Reloading navigation on every event has a measurable fixed cost |
| Local metadata listing with one attachment | All 1,048,591 content bytes fetched | Metadata requests should not transport file bodies |
| Local list invalidation with 3 versus 103 members | 15 versus 115 statements | Registered membership count drives an N+1 query pattern |
| Local detail history after fixture growth | All 1,001 events fetched | List pagination does not bound record detail history |

Counts include BEGIN/COMMIT and role/tenant setup. Local LiveView probes use the SQL sandbox; asynchronous presence can move a few statements between event windows. Hosted reads use the actual runtime role but exclude browser/network latency. No other application SQL was captured during the hosted idle window. These diagnostics establish costs and growth patterns, not maximum user capacity.

The hosted instance currently contains one organization, 15 memberships, 15 tickets, 48 events, no private documents, and no pending outbox messages. Its limits remain two application CPUs, one PostgreSQL CPU, and a pool of ten connections. `pg_stat_statements` is absent. The [earlier nine-run browser campaign](benchmarks/school-shared-host-2026-10-27/report.pt-BR.md) used a different, frozen 12-ticket baseline and sampled PostgreSQL near its CPU quota under load. Repeat that controlled workload with database instrumentation before attributing the loaded bottleneck to a particular query or lock.

## Guarantees that every change must preserve

| Contract | Required preservation |
| --- | --- |
| Organization isolation | Non-owner runtime role, transaction-local tenant settings, RLS, composite ownership constraints, and fail-closed missing/wrong scope; no pooled session-level tenant settings |
| Current authority | Active user/membership/organization, grants, relationships, assignments, and session validity are checked at the appropriate operation boundary; cached scope is not authority |
| Revocation ordering | Permission changes, suspension, and mutations retain their serialization guarantees; a command waiting behind revocation must reauthorize and fail when access has gone |
| Concurrent work | Same-section conflicts preserve drafts; different sections may both save; transitions validate the reviewed revisions; budgets cannot overspend |
| Durable commands | Business writes, receipts, audit, and outbox intent remain atomic; replay reauthorizes and checks the payload digest |
| Live convergence | PubSub remains an invalidation mechanism, Presence remains advisory, and lost/duplicate/out-of-order notifications recover; retain connected reconciliation within the configured 30 seconds |
| Pinned behavior | Existing tickets retain their immutable versions and mappings; current authorization facts remain live; historical data remains readable under its policy without reviving retired writers |
| Confidential projections | Authorization precedes counts, pagination, history, documents, recipient discovery, and public projection; hidden fields and identities never enter UI/event/metric payloads |
| Reusable definitions | No school names, workflow keys, or example-specific fast paths in shared runtime code; preserve independent school, restaurant, equipment, and combined-capability recreation |
| Resource bounds | No external calls or password hashing while holding a business transaction; no persistent process per ticket; bounded queues, reads, and retention batches |

## Delivery sequence

Each step is a separately reviewable change or a short series of cohesive PRs. Keep performance evidence attributable to one step. Steps 2 and 3 can be developed independently after step 1; later integration remains sequential.

| Step | Scope | Dependency and release condition |
| --- | --- | --- |
| 1 | Reproducible measurements and benchmark deployment | Establish comparable baseline and operation-level telemetry before tuning |
| 2 | Metadata-only document reads | Prove zero file-content bytes in metadata reads and unchanged document permissions |
| 3 | Due-work dispatch and separate retention cleanup | Preserve recovery, expiration, and tenant fairness while removing empty-tenant work |
| 4 | One authorized unit of work per composite read | Preserve current lock behavior first; eliminate repeated scope/context setup |
| 5 | Lightweight live events and batched invalidation | Build on step 4; preserve drafts, permissions, and notification convergence |
| 6 | Bounded detail history and supporting projections | Preserve full authorized history through pagination, with stable cursors |
| 7 | Read-compatible and narrower business locks | Require independent-connection overlap tests; keep distinct lock changes separate |
| 8 | Hosted comparison and deployment | Meet correctness and efficiency gates on fixed resources, then evaluate residual SQL plans |

### Step 1 Establish measurements and an isolated rollout path

**Increment 1a:** the opt-in `Instantflow.Diagnostics.QueryProbe` and `test/instantflow/db_efficiency_test.exs` promote the 13 local measurement scenarios into repeatable checks. The probe exports fixed-cardinality aggregates for statements, returned rows, decoded binary/content bytes, query/queue/decode time and elapsed time. It retains no SQL, parameters or result values and detaches on completion, exceptions and owner termination. It is disabled outside explicitly requested captures. The [new local baseline](evidence/db-efficiency-step1-baseline-2026-11-06.json) reproduces the earlier counts, including 412 statements for opening a record, 153 for heartbeat, and 301 for a ten-organization empty drain.

Run the scenarios against a fresh test partition; use a new report filename because reports append one JSON object per scenario:

```sh
MIX_TEST_PARTITION=_efficiency_<unique_suffix> \
DB_EFFICIENCY_REPORT=.local/efficiency-<run>.jsonl \
mix test test/instantflow/db_efficiency_test.exs --seed 0
```

The existing fixtures roll back after each test and background workers are disabled. Caller-only captures can run alongside other processes; the lifecycle harness explicitly uses `scope: :all` to include LiveView processes and must run without unrelated traffic. Event windows include synchronous replies and work already processed by the view, **not a guaranteed complete deferred save cycle**. A committed-delivery barrier and separate background windows, complete connection-lease instrumentation, observer-overhead measurements, and hosted database/cgroup sampling remain step 1 work. Decoded binary bytes are not wire bytes or heap usage. The document-content metric is the exact sum of returned `content` binary values.

The manual [benchmark candidate workflow](../.github/workflows/benchmark-candidate.yml) accepts a successful Checks run ID for its exact selected revision, builds ARM64, and publishes an artifact containing the immutable digest, application commit and Checks identity. It has a separate concurrency group and no deployment job. Once the workflow is available on the default branch, select the candidate branch in Actions and supply its successful push/manual Checks run ID. A failed, pending, different-commit, other-workflow or fork run is rejected. The guarded benchmark deploy/restore command and runner manifest support are still required before hosted rollout; publication alone does not complete step 1. The workflow has been parsed locally and its provenance checks tested; an Actions build has not yet been run.

Validation for increment 1a: `mix precommit --seed 0` passed 396 tests; deployment-tool checks passed 11 tests. An initial randomly seeded run hit two intermittent existing LiveView failures (sandbox queue timeout and upload-channel cancellation during revocation); both passed in isolation and in the complete rerun. No timeout or assertion was relaxed. These races remain follow-up health-review findings, not established fixes from the diagnostic work.

Promote the diagnostic method into a repeatable harness. Record operation duration, SQL count, query/queue/decode time, connection lease duration, rows and bytes fetched, and follow-up notification work. Separate HTTP mount, connected mount, draft, reason, heartbeat, save, remote refresh, history page, and list/board reads. Attribute background work separately. A save measurement must include both immediate work and the bounded follow-up refresh window; moving work after acknowledgement is not an efficiency improvement by itself.

Export bounded aggregates through an actual telemetry reporter. Use operation names and normalized query identifiers; exclude tokens, SQL parameters, names, field values, and unbounded tenant/user/record labels. Keep telemetry handlers lightweight. Measure observer overhead and use the same instrumentation for baseline and candidate.

On the dedicated benchmark database, enable `pg_stat_statements` and collect before/after statistics, lock wait samples, database CPU seconds, cgroup throttling deltas, WAL, I/O, temporary files, and outbox age. PostgreSQL requires `shared_preload_libraries` configuration and a restart for this extension; schedule that only for the benchmark cluster. Use counter deltas rather than resetting global statistics during unrelated observations. Ecto queue measurements alone do not describe the entire time a composite operation holds a connection. See [PostgreSQL statement statistics](https://www.postgresql.org/docs/16/pgstatstatements.html).

**Acceptance:** deterministic query-count scenarios use a fresh migrated database, separate actors, fixed payloads, and drained prior notifications. Real browser runs record the exact image, fixture hash, limits, network path, instrumentation settings, and generator load. Finish or abort every run with the temporary observer detached and its timers/processes cleaned up.

### Step 2 Fetch document metadata without file bodies

**Increment 2a:** metadata, object lookup, attachment validation and readiness queries now select explicit columns without content. List visibility predicates are applied in SQL before fetching document rows. Review and download prove current authority and state using metadata before fetching one body; receipt replay, explicit rejection and deletion fetch none. Successful review no longer sends the unchanged body back in its UPDATE. The existing tenant, actor and ticket locks are preserved.

The maximum-size fixture (5,242,880 bytes) returns zero content bytes for metadata, with approximately 5.6 KB of decoded binary data across the entire authorized operation. The matching 1 MiB baseline scenario drops from 1,048,591 content bytes to zero. The [document measurement evidence](evidence/db-efficiency-documents-2026-11-06.json) includes denied/revoked/cross-tenant reads, quarantine, expiry before cleanup, attachment saves, transition guards, receipt replay, checksum rejection and authorized review/download. Focused document/context/LiveView tests pass (20 tests), and `mix precommit --seed 0` passes 405 tests for increment 2a. No hosted image or database was changed.

**Increment 2b:** `list_page/3` now returns 50 authorized metadata rows and an exclusive ID cursor; `list/2` returns the newest page. The request view provides older/recent navigation and replaces its document stream per page, preserving drafts and the chosen page during reconciliation. Visibility and cursor predicates precede LIMIT. At 1, 1,001 and 10,001 retained documents, the query fetches 1, 51 and 51 metadata rows respectively (one lookahead), with zero content bytes. Decoded binary data remains 6,808 bytes in both larger cases. See [pagination evidence](evidence/db-efficiency-pagination-2026-11-06.json).

The previously intermittent upload/revocation failure was reproduced and fixed while validating this increment: revoked views now clear protected state and redirect, allowing LiveView teardown to stop monitored upload channels. They no longer synchronously cancel a potentially dead upload channel before redirecting. Deterministic tests queue revocation before the upload's DOWN message in both request and participant views, then await redirect within the documented one-second UI budget instead of ExUnit's generic 100 ms default. Cancellation while remaining on an authorized page is unchanged. Validation: 21 focused document tests, two targeted teardown tests, assets build, and `mix precommit --seed 0` (409 tests, zero failures).

Change `PrivateDocuments.list/2` and related metadata/reference/readiness paths to select only the columns they need. Build readable field/section predicates before fetching metadata. Preserve full content selection for authorized downloads and integrity review. Retain the database storage design for now; external object storage is a separate capacity decision.

Audit `document!/2`, `ready_ref?/3`, and attachment validation as well as the visible list: a guard that needs status, expiry, size, or ownership should not decode a multi-megabyte body. Bound historical metadata independently of the 20-active-file quota.

**Acceptance:** capture actual SQL result columns/bytes for an authorized metadata read, denied read, attachment guard, review, and download. Metadata and readiness checks fetch zero content bytes. A maximum-size attachment fixture stays below the existing 4 MiB ordinary-read budget. Existing quarantine, expiry, checksum, release, receipt replay, retired-version, and cross-tenant tests pass. Download/review retain their explicit file-size limits.

### Step 3 Poll due work and move retention to its own schedule

**Increment 3:** delivery now discovers a bounded rotating page of active organizations with pending messages. Empty delivery and maintenance passes each issue one SQL statement at 1, 10 and 1,000 organizations. Delivery retains its 250 ms recovery poll, per-organization quota, current tenant checks, durable coalescing and ticket-before-message lock order. A failed tenant no longer prevents the rest of the page from progressing. The calculation dispatcher still uses the original discovery function.

Retention now runs independently every 60 seconds by default, visiting up to 50 due organizations and clearing up to 100 rows per category per organization. Each batch selects and locks a fixed set of IDs before updating those rows, skips competing locks, and retries on later sweeps. A regression test caught an UPDATE with a locking LIMIT subquery clearing more than its intended bound; materializing the selected IDs inside the same transaction fixes that behavior. Logical document expiry, active-file quota release and terminal calculation expiry are enforced before cleanup. Retired data and queued/running calculations are preserved. Configuration and deployment requirements are in [operating boundaries](deployment.md#polling-capacity-and-reconciliation).

The [background evidence](evidence/db-efficiency-background-2026-11-06.json) records a real ten-minute local run with ten empty organizations, the non-owner runtime login and pool ten: 2,380 delivery passes plus ten maintenance passes produced **2,390 SQL statements**, zero errors and zero worker failures. A separate equal-pass test uses 2,400 delivery passes and ten retention passes: 2,410 measured statements versus 722,400 calculated from the measured old 301-statement pass, a **99.67% reduction**. The old version was not rerun for ten elapsed minutes. Unrelated local tests shared the PostgreSQL server during the candidate window, so its timing fields are diagnostic only; no hosted latency or capacity gain is claimed.

Real independent-connection tests verify duplicate dispatchers commit only one attempt, a failed tenant rolls back while another progresses, and retention skips then resumes a locked row. Other regression coverage includes flooded-tenant rotation, worker restart without wakeups, suspension/resumption, strict retention bounds, immediate expiry and retired history. The additive migration fixes function search paths, revokes PUBLIC execution, returns only organization IDs and requires the existing privileged operator; runtime-role RLS remains enforced. No index was added without a representative plan. Skewed backlog plans, continuous metric export, physical-retention lag under load and hosted comparison remain acceptance work.

Validation: 29 focused background/calculation/document tests, 27 runtime-role tests, five recreation/recovery tests, and the final `mix precommit --seed 0` run passed **423 tests, zero failures**. The populated forward migration preserves all business rows, and dump/restore retains discovery permissions and supported behavior. The first full run reproduced the earlier recreation-test queue timeout: action helpers had accumulated unused subscribed LiveViews on one sandbox connection. Commit `3c307fa` closes those helper views after assertions while retaining explicitly opened scenario views. The final gate passed with unchanged queue settings; independent-connection concurrency coverage remains in place.

Reproduce the elapsed idle observation with `MIX_ENV=test mix run --no-start scripts/benchmark_idle.exs`. It creates and migrates a local disposable database, uses a real runtime login and pool ten, runs both workers for ten minutes, detaches observers, stops the application and removes that database. `IDLE_BENCHMARK_DURATION_MS`, `IDLE_BENCHMARK_ORGANIZATIONS` and `IDLE_BENCHMARK_REPORT` optionally control the duration, fixture size and output file. The default report is `.local/idle-benchmark.json`. Run without other local load when comparing timings.

Replace enumeration of every active organization with a narrowly scoped control-plane function that returns a bounded, rotating page of active organization IDs with pending work. It must not return ticket IDs, payloads, or arbitrary tenant data. Re-establish RLS scope and recheck organization availability before processing each batch.

If implemented as a security-definer function, fix its search path and grant execution explicitly to the runtime role. Keep its SQL and returned columns narrowly defined and covered by runtime-role isolation tests.

Introduce delivery-specific discovery rather than silently changing `dispatch_organizations()` for all callers: `Calculations.Worker` also uses that function, and its queued/leased work has different eligibility rules. Test calculation processing independently even though Python execution remains disabled in the hosted school benchmark.

Keep the existing per-organization delivery quota and durable revision coalescing. Use post-commit wakeups for prompt processing if useful, with periodic due-work discovery as recovery when a wakeup is lost. Preserve fair scheduling under a flooded tenant. Multiple application nodes must not duplicate business effects; do not introduce a new job framework merely to remove polling overhead.

Move document/calculation retention into an independently supervised, bounded maintenance job with a configurable initial 60-second cadence, a per-batch row limit, stable progress, and retry metrics. Validate that cadence against retention requirements before rollout. Expired documents must become unusable at the deadline even if physical clearing runs later; apply the equivalent rule to calculation snapshot access. Retired data exclusions remain intact. A large cleanup backlog must not delay live updates or hold a connection for an unbounded transaction.

Candidate indexes, subject to representative plans: partial pending-outbox `(organization_id, id)`; document expiry `(organization_id, expires_at, id)` for live states; calculation retention `(organization_id, inserted_at, id)` for eligible terminal runs. Avoid adding overlapping indexes without measuring writes, size, and plan benefit. Generate any migration with `mix ecto.gen.migration`.

**Acceptance:** an empty delivery pass takes at most five statements as active organization count grows from 1 to 10 to 1,000. Count maintenance separately and also require at least 90% less total idle SQL over a ten-minute window with ten empty organizations. Verify missing wakeups, worker restart, rollback/retry, suspension, duplicate dispatchers, unchanged-revision delivery outcomes, retention backlog, and unequal tenant load. Adding `SKIP LOCKED` must not reverse the existing ticket/message lock order.

### Step 4 Compose reads inside one current authorization boundary

**Increment 4a:** workflow detail reads, commands and receipt replay now use the fresh membership/grants already supplied by `Tenant.transaction`; they no longer open a nested scope reload. The private read helper cannot receive an external cached scope. Tenant setup reads the previous role and organization together and restores both together, including inside existing transactions. Authorization gates, user/membership locks, role switching, rollback behavior and organization checks remain in place. This is an initial reduction, not the complete composite record projection.

The matching local probe reduces a detail read from 31 to 17 statements, both record mounts from 412 to 318, idle heartbeat from 153 to 113, reason change from 29 to 25, and save/refresh from 366 to 259. These are the existing synchronous diagnostic windows; complete deferred-cycle and hosted measurements remain pending. New tests require one user, membership and grant load for reads, commands and receipt replay, reject a revoked cached actor, and verify nested settings restoration after success and exceptions. See [authorization evidence](evidence/db-efficiency-authorization-2026-11-06.json).

Validation: 41 focused authorization/isolation/runtime-role/diagnostic tests and `mix precommit --seed 0` passed 425 tests with zero failures.

Introduce an explicit internal API for already-authorized operations. Public context entry points still prove scope; internal projection/control helpers receive the fresh scope and fetched policy facts from the enclosing tenant transaction. A reusable context must be bound to the current process, organization, and transaction lifetime, and must not become a socket assign, cross-request cache, or authority passed into spawned tasks. Server-internal call discipline must be explicit and tested.

Start with `WorkflowRuntime.get`, `RequestLive` loading, assignment/participant/communication controls, and presence. Fetch the ticket, immutable version, current grants, and relevant relationship/assignment facts once. Reuse the existing policy functions with supplied facts rather than issuing a query for each predicate. Extract a cohesive authorized record projection service; LiveViews retain forms, drafts, navigation, and rendering.

Consolidate nested `Tenant.raw` setup and restoration without weakening scope mismatch detection. If the boundary owns the outer transaction, transaction-local settings naturally expire at commit/rollback. If called inside a pre-existing transaction, restore the prior role/context correctly. Test privileged fixture connections and the real non-owner runtime login. Avoid broadly changing transaction semantics and lock modes in this PR.

Release the connection before rendering, external calls, or expensive password hashing. Review the router-wide `Repo.checkout` wrapper once composite reads have their own lease: today it spans the login controller's password verification. Measure checkout count and lease duration together so reducing round trips does not create longer connection occupancy.

**Acceptance:** a detail projection uses one scope/grant load per authorized boundary, with bounded batches for supporting facts. Public helper misuse fails closed; nested rollback, wrong-tenant nesting, task reuse, and pooled connection reuse preserve isolation. Existing command receipts, atomic capability composition, pinned version behavior, and read-policy parity pass unchanged.

### Step 5 Make routine events cheap and coalesce notifications

**Increment 5a:** presence now projects only current access shape and authorized peer identities. It loads the pinned ticket/version, current grants, and bounded batches of relationship/assignment facts; it does not read section values, history, file bodies or control directories. Peer role/department eligibility uses the same assignment predicate as normal record access. Peer queries select names without user password hashes. The viewer's tenant authorization gate and current membership checks remain mandatory; presence remains an advisory snapshot and cannot authorize a command.

Unchanged heartbeats and presence updates now refresh that small projection. A changed authorization fingerprint, ticket revision, pinned version, retirement status or readable/editable section set triggers normal reconciliation, preserving authorized drafts and discarding revoked ones. Ticket/delivery invalidations and the 30-second reconciliation still perform full refreshes, including delivery changes that do not increment the ticket revision. A denied draft event cannot reinsert an obsolete stream row before reconciliation.

Matching local lifecycle counts are 312 statements for both mounts, 39 for unchanged heartbeat, 25 for reason, 41 for draft, 173 for save/refresh and 112 for ticket invalidation. Heartbeat/reason/draft windows contain no history or document queries. Presence projection costs 16 statements for both 3 and 103 peers; participant presence costs 17 without reading documents. Missed permission broadcasts, missed record invalidations, current named assignments, participant revocation, retirement, inactive peers and preserved drafts have explicit regression coverage. The mount/heartbeat/reason/save targets are **not yet met**. Composite reads, navigation reuse, input debounce and duplicate refresh coalescing remain work; recipient batching is addressed in 5b below. The budgets are unchanged.

Validation: 53 focused context/LiveView/runtime-role checks and `mix precommit --seed 0` passed 431 tests with zero failures. See [presence evidence](evidence/db-efficiency-presence-2026-11-06.json). A new stale-draft regression initially exposed an obsolete stream insertion during revocation; denying the draft before insertion and clearing a no-longer-editable active section fixes it.

**Increment 5b:** list invalidation now walks active memberships/users in stable pages of 250 and loads grants and supporting policy facts per batch. Presence and notification paths share the transaction-bound grant/fact loaders and the existing policy evaluator. Confidential assignment eligibility, verified participants and current role/department matching remain part of recipient selection; inactive users are excluded. Three and 103 registered members both require **11 statements**, down from the initial 15 and 115 respectively (13 and 113 after increment 4a). At 1,003 members, five batches require 19 statements. See [notification evidence](evidence/db-efficiency-notifications-2026-11-06.json). This removes per-member SQL; per-pass notification deduplication and narrower finance invalidations remain pending.

Validation: 47 focused notification/presence/delivery/runtime-role tests, the asset build, and the final `mix precommit --seed 0` run passed **435 tests, zero failures**. The complete gate also checks that nonempty grant/fact batches reject use outside an enclosing transaction. Final lifecycle captures vary by one statement for draft/save as asynchronous work enters the window (draft 41–42; save 172–173); complete deferred-cycle measurement remains pending.

Separate session/current-access validation from workspace-navigation projection. Recompute navigation at mount, relevant permission/catalog changes, and periodic reconciliation, while retaining current authorization on protected operations. If navigation caching is introduced, it must not retain newly unauthorized labels or become permission evidence; test its invalidation and missed-event recovery explicitly.

Compare the freshly loaded authorization facts with the navigation's permission fingerprint on each protected operation. If it changes, clear or rebuild navigation before rendering, even when the permission broadcast was lost. Include a catalog generation if publication changes require the same immediate guarantee; do not substitute a long TTL for those checks.

Give Presence a small authorization/fact query that establishes whether the actor may edit the named section and which peer identities the viewer may see. Do not fetch full history, files, calculation runs, or candidate directories for a presence heartbeat. Batch peer permission facts rather than calling `WorkflowRuntime.get` for each peer. Coalesce presence updates and use an initial 250 ms debounce for text changes, with an immediate submit carrying the current values. Preserve focus, dirty forms, explicit conflict/reapply behavior, and disconnect handling.

Replace the per-member `Access.load` loop in `invalidate_lists` with authorized recipient selection or bounded batches of grants and policy facts. A batch must preserve confidential recipient semantics, including externally linked and named-assignment users. Publish at most one list invalidation per recipient/topic per dispatcher pass. Scope finance invalidations to relevant changes rather than every ticket update.

Coalesce duplicate socket refresh requests into one pending read. A ticket revision alone is not a complete freshness token: delivery outcomes can change without a new ticket revision, and permissions/session validity can change independently. Preserve distinct invalidation reasons or explicit projection generations; do not skip reauthorization because a revision is unchanged. Continue minimal authorized event payloads and the 30-second reconciliation path.

**Acceptance:** heartbeat/reason/draft measurements fetch no full history, document content, or directory candidate lists. Increasing peers or registered members adds bounded batch work rather than one full read per person. The 3-to-103 member invalidation scenario adds at most two statements when both fit one batch. Test multiple tabs, revoked peers, permissions changed without ticket edits, delivery-only updates, missing/out-of-order broadcasts, and fast typing followed immediately by submit.

### Step 6 Bound detail history and supporting collections

Split the current-state projection from history, deliveries, historical documents, and calculation attempts. Keep current controls eager and small; fetch a bounded first history page when displayed and subsequent pages on demand. Use a stable keyset cursor such as ticket revision, with an initial history page size of 50. Apply visibility in the authorized query before LIMIT; filtering a raw 50-row page afterwards can hide available results and expose misleading counts/cursors.

Retain immutable events and full authorized navigation through history. Avoid constructing an unbounded `event_ids` list for delivery reads. Use the appropriate authorized join/predicate and its own bounded page. Prevent full collections from remaining in both a long-lived socket assign and a stream. Use existing indexes where sufficient before adding new ones.

**Acceptance:** changing history volume from 1 to 1,001 to 10,001 events does not increase first-page row count or payload beyond the page bound. Hidden newer events, new appends during pagination, old pinned versions, and delivery visibility produce neither duplicates nor unauthorized metadata. Routine heartbeats do not reload historical pages.

### Step 7 Refine locks after read composition is stable

Separate read authorization from mutation locks. Evaluate `FOR SHARE` for the user/membership facts needed by a read while retaining the shared authorization advisory gate and organization lock. It allows concurrent readers and still conflicts with updates; `FOR KEY SHARE` alone would not block all relevant non-key changes. Validate the exact deactivation/revocation paths before selecting the final modes. PostgreSQL's [row-lock conflict matrix](https://www.postgresql.org/docs/16/explicit-locking.html#LOCKING-ROWS) is the reference.

Remove the ticket `FOR UPDATE` requirement from metadata-only reads where protected facts remain consistent under the authorization boundary. Mutations, downloads that write audit, integrity review, and transition checks keep the locks their invariants require. Choose read versus write mode at the outer boundary; forbid implicit read-to-write lock upgrades, which can deadlock when concurrent readers both upgrade.

In a separate change, narrow the organization-wide operations advisory lock. First prove isolation between workflows, then consider session/resource locks. Daily closing still needs an exclusive gate against all writes for its workflow/business date; ordinary writes may take a compatible shared gate before locking their specific resources. Keep a single documented order across organization, authorization, actor, operation gate, ticket/resource, section, budget, and receipt rows. Audit cross-capability paths before changing that order.

**Acceptance:** independent database connections and deterministic barriers prove concurrent read overlap, including the same user in two organizations and different users reading one ticket. Re-run read/revocation, write/revocation, same/different section saves, competing transitions, save/approval, budget contention, duplicate commands, resource occupancy, and close-day/write races. Assert persisted outcomes and absence of deadlocks. Shared sandbox tests alone cannot pass this gate.

### Step 8 Compare on the hosted benchmark and release incrementally

Run focused measurements after each relevant PR and the complete matrix for an integrated candidate. Preserve the existing 10-organization, 10,000-ticket, 50-reader/actor tests and the school/non-school recreation and populated recovery suites.

Keep pool size ten and the existing CPU/memory quotas during the first comparisons. Only after eliminating unnecessary work should evidence justify pool sizing, additional indexes, immutable-definition caches, or more database CPU. Cache only immutable published bodies/mappings by organization and immutable version identity, with explicit memory bounds; keep mutable grants, relationships, assignments, retirement state, and session decisions current.

If significant SQL remains, rank normalized statements by total execution and planning cost. Obtain `EXPLAIN (ANALYZE, BUFFERS, WAL)` under the runtime role and matching tenant context on disposable benchmark data. Do not benchmark an owner-bypass-RLS plan or run write plans against retained data. Include large history, many distinct policy versions, and skewed tenant volume before deciding on indexes or materialized read models.

## Acceptance budgets

These are proposed engineering targets, to be fixed in step 1 before implementation. They are not achieved results. Rebaseline only when the scenario changes explicitly; do not loosen a budget after a failing run without documenting the tradeoff.

| Scenario | Current local count | Proposed limit |
| --- | ---: | ---: |
| Record open, both mounts | 412 | 160 statements |
| Idle record heartbeat | 153 | 25 statements; no history/navigation/file-body reads |
| Transition reason event | 29 | 20 statements; no navigation read |
| Save and its normal immediate refresh | Approximately 370 | 120 statements; measure deferred follow-up separately and in the combined cycle |
| Empty dispatcher, 10 organizations | 301/pass | 5/pass, independent of empty tenant count |
| Metadata response | Entire file body fetched | Zero content bytes |
| First history page | All events | At most 50 authorized events |

Retain the established documented-environment budgets: p95 accepted backend command and authorized backend read at most 500 ms; p95 committed update visibility and browser page completion at most one second; at most 4 MiB fetched ordinary-read payload and 32 MiB incremental BEAM memory per in-flight read. File download/review use their separate explicit file limits. Missed-event recovery remains within the configured 30 seconds while connected.

For the fixed ten-user VPS school scenario, propose at least 25% lower save-ack p95 and 40% lower database CPU seconds per completed read/save cycle against a freshly rerun baseline. Require zero unexpected functional failures, no persistent queue growth, and no material read/visibility regression. These are new comparison goals, distinct from the existing backend budgets. Report per-run variation; do not compare a new candidate only with the historical October result. In a closed workload, lower latency raises throughput and can raise CPU utilization, so compare CPU per business cycle and add an equal-offered-rate comparison before claiming improved headroom.

## Benchmark matrix and correctness gate

| Workload | Purpose |
| --- | --- |
| Idle with 1, 10, and 1,000 active organizations | Expose empty polling/cleanup cost; include a ten-minute aggregate window |
| Connected idle, typing, and save with 1, 5, and 10 distinct users | Attribute UI amplification; use existing school-v1 baseline for comparable browser campaigns |
| Two and five editors on one ticket | Measure refresh bursts and expected conflicts while proving draft preservation and independent-section behavior |
| 3, 103, and 1,003 registered members; small and large peer sets | Prove recipient/presence batching; separate registered members from connected browsers |
| History of 1, 1,001, and 10,001 events; files up to the supported quota | Verify bytes/rows and latency remain bounded for ordinary detail reads |
| Ten tenants, 10,000 records, 50 actors; equal and uneven load | Retain existing command/read/visibility and tenant-fairness acceptance |
| Mixed versions, 100 processes/pins, wide fields, participant and confidential views | Retain the Sprint 11 supporting-volume matrix and policy equivalence |

Run local tests/builds/fixture generation outside timed windows. Use production assets for browser checks. For the hosted 1/5/10-user comparison, retain three repetitions per level, 60-second warmup and 180-second measured windows; balance baseline/candidate order to reduce shared-host bias. Keep normal VPS services running. Stop a load step if correctness fails, latency/queues grow without recovery, or the generator/host loses headroom; record the stopping point rather than presenting it as sustainable capacity.

Mandatory regression entry points include `runtime_role_test.exs`, `tenant_isolation_test.exs`, `refresh_delivery_test.exs`, document/participant policy tests, finance accounting, operations lifecycle/read-model tests, collaboration LiveView tests, pinned navigation, and `sprint11_supported_recovery_test.exs`. Extend these for the changed invariant instead of replacing them with query-count assertions. Run `mix precommit`, assets, relevant Python checks, independent-connection races, and populated forward-migration/restore before integrating a candidate.

## GitHub Actions and benchmark deployment

The current [Checks workflow](../.github/workflows/checks.yml) invokes [publication and redeployment](../.github/workflows/deploy.yml) only on `main` after foundation succeeds. It builds ARM64 and targets `/home/ubuntu/apps/oracle-caddy`, the serving application. The benchmark lives separately at `/home/ubuntu/apps/instantflow-benchmark` with a pinned digest. A normal push does not update benchmark Compose configuration, PostgreSQL settings, or its selected image. See the [deployment reference](../deploy/README.md) and [benchmark runbook](../benchmarks/k6/README.md).

1. Add a benchmark-specific manual workflow, or split image publication from serving deployment so a selected, CI-verified `codex/` candidate can be built without first deploying it to the serving application. Give benchmark runs a separate concurrency group. Publish and record an immutable ARM64 image digest.
2. Add a benchmark deployment command with a fixed path/project/database guard, host lock, current-state backup, optional operator-only migration step, image selection, health wait, and authenticated smoke. The existing production deployment script is not this command, and the current benchmark Compose file has no migration service. Keep operator credentials out of the web container.
3. Extend runner metadata to distinguish the archived fixture's source commit from the tested application commit/digest. The current runner hardcodes the baseline image and rejects a different image; replace that with explicit baseline/candidate manifests and verification, not an unchecked bypass.
4. Before resets, preserve the current benchmark state, image digest, relevant configuration, and freshly verified counts in a private snapshot. There were 15 tickets at review time; capture the actual state at execution rather than assuming that count remains fixed. Restore the frozen school-v1 baseline for each timed repetition, apply required forward migrations, and verify fixture semantics. At campaign completion, restore the preserved state with a schema-compatible image. Keep data restoration distinct from an application-only rollback.
5. Keep observability settings, pool, quotas, generator, and route identical across a comparison. Verify the direct-origin TLS route for the current egress address; do not silently mix Cloudflare-proxied and direct-origin timings. Do not pause unrelated services.
6. After the candidate passes, promote the reviewed source to `main` through the normal checks/deploy workflow. Verify running revision, health, protected reads, and live updates. Existing pre-deploy backups remain required. Use forward-compatible schema changes; an incompatible migration needs a tested restore/cutover plan, because the current workflow does not automatically roll back images or schemas.

## Completion and next implementation

Increments 1a, 2a, 2b, 3, 4a, 5a and 5b cover measurement, body-free bounded document browsing, due-work dispatch, independent retention, fresh authorization reuse, lightweight presence and batched list invalidations. Complete the composite read boundary, navigation reuse and refresh coalescing, together with deferred-work/lease measurement and guarded benchmark rollout. History timestamp formatting currently calls PostgreSQL per row during rendering and is another concrete batching opportunity. Leave lock refinement until the cheaper read paths and their concurrency tests are stable.

The work is complete when the candidate meets the fixed efficiency targets, preserves every correctness gate, passes the existing generalized workflow/recovery matrix, and records reproducible local and hosted results with the exact deployment and fixture identities. Update this plan with measured outcomes per step rather than marking progress from code changes alone.
