# Sprint 11: review of the latest three checkpoints

Reviewed 2026-10-23 at b6b636223e893d3762b6ec8bc299035010dc5987.
The repository was clean at the start. Scope:

1. e07ea2a — operational and retirement checkpoint, including the accepted fixes.
2. 7f0e5ad — bounded idle-version supporting reads and measured backend cases.
3. b6b6362 — pinned operational page navigation across publications.

## Assessment

The three increments maintain the intended shared builder architecture. The first
retains its earlier acceptance; the second is acceptable as a limited T02 increment,
not full scale acceptance. The third repairs actual pinned-page navigation but
introduces an overly broad context read. Correct the finding below before accepting
its authorization boundary. Sprint 11 correctly remains In progress, 1/5.

## P2: Old-session admission releases current-only session data

Location: lib/instantflow/operations.ex:88-117, particularly the authorization at
line 95 followed by the process-wide session query at lines 111-117.

Operations.workspace/4 authorizes the supplied session's pinned version, then
returns all open sessions and a process-wide report. A user whose old pin admits
them can therefore receive data about a newer session whose pinned permissions
explicitly exclude them. Supplying an old session changes the authority used for
the whole workspace without narrowing the resulting projection.

Independent reproduction:

- Publish an operational version admitting an operations grant and open a session
  as that granted staff member.
- Publish a newer version admitting only admin, and open a different resource
  session as admin with a distinct captured operator name.
- Confirm that both the current workspace and direct newer-session visit return
  nil for the former operator.
- Call workspace with the old session ID. Its sessions collection contains the
  denied newer session, including its captured operator/resource names and IDs.

The probe fails on that last assertion. ProcessLive removes the current-workspace
blocks from the historical page, but still assigns the returned report and streams
resources associated with these sessions into server-side state. The demonstrated
issue is an authorization/projection inconsistency at the context boundary; the
probe does not establish that the hidden data appears in rendered browser HTML,
nor a cross-tenant leak or unauthorized mutation.

Correction: give old-session pages a narrow session projection. Keep the specific
session, its authorized batches/actions and the catalog data deliberately needed
for continuing its item-entry contract. Do not fetch/return unrelated sessions,
resource occupancy or process-wide reports merely because one old pin admits the
user. Shared workspace data must require its separately applicable current
permission. Keep this in the context/query boundary, not just template conditions.
Add denied-newer-session and report/metadata regressions alongside current grant
revocation, isolation and successful old-session settlement tests.

## Checkpoint-specific conclusions

### Operational retirement

The previously reviewed archive state and pinned opening-replay fixes remain in
place. Full-suite verification includes populated operational migration/restore,
resource reuse, retained unpaid versus paid amounts, revocation and no-duplicate
receipt coverage. No new actionable finding was identified in this checkpoint.

### Read-support scaling

Referenced-version pruning uses an organization/version EXISTS predicate in the
existing projection service; it does not filter unauthorized records after paging.
Projection predicates are restricted to pins represented on the selected page.
The added tenant/version index supports that lookup. Existing mixed-pin/count/
revocation tests and the quantitative idle-version regression remain in the suite.

The benchmark report distinguishes backend timings, serialized Erlang term sizes
and sampled caller memory from browser latency, wire bytes and full BEAM peak.
It retains the unindexed intermediate result and slower cases. This is appropriately
limited evidence: active-pin growth, operational lists/reports, process discovery,
complete memory and browser measurements still need the declared T02 acceptance.
The review inspected the harness and retained reports; it did not rerun the full
13-case before/after benchmark matrix or independently certify those timings.

### Pinned navigation

Minimal pinned-version resolution, old page keys/payment choices, current revocation
and same-process ownership checks are sound. Tests exercise rendered checkout after
republication and read-only pre-capability history. The remaining correction is
that permission to finish one old session must not become broader read permission.

## Independent verification and limits

- mix precommit: 294 tests, zero failures, seed 599171.
- Additional probe: one failed assertion, seed 332077, in
  .local/sprint11_navigation_review_test.exs.
- git diff --check passed before this report.

No production code changed. No deployment, browser timing or full load matrix was
run by this review. Previously recorded intermittent LiveView token/reload failures
remain unexplained; a passing current suite does not establish their resolution.

## Execution follow-up — 2026-10-23

The P2 projection finding is addressed in the
[resolution report](sprint11-three-checkpoints-review-resolution.md). Historical
workspace reads now exclude unrelated sessions, resource occupancy and daily
reports at the context boundary. The report records regression and validation
evidence; the review's original findings and limits above remain historical.
