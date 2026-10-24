# Independent review follow-up — 2026-10-24

The two implementation findings are addressed. Historical acceptance and seminar
artifacts are retained with their measurement boundaries.

## Board discovery (P2)

Previously every populated pin's full definition participated before the version
selector was sliced. StageBoards now delegates to BoardVersions, which:

- Reads only the authorized latest ID, without returning its definition.
- Scans populated pins with a descending-ID keyset and at most 25 compact policy
  definitions per query. Candidate payload excludes fields, stage descriptors,
  transitions, descriptions and unrelated views.
- Applies the existing view/section policy compiler to each batch before retaining
  only admitted ID/number options. An authorized current board can still be empty.
- Fetches exactly the selected full definition for card filtering/projection and
  ordered stage display. Current authorization is held through Tenant throughout.

No published schema, cached authority or second policy engine was introduced.
Existing historical selection, revocation, private-field, foreign-organization,
per-column paging and LiveView tests remain applicable. A new regression crosses
a 25-pin boundary with distinct hidden publications and checks the compact payload.

Discovery still scans all populated pins. CPU/query work and authorized option
metadata grow with pin count; batching limits simultaneously loaded definition
bodies, not overall capacity. Database JSON extraction also does real work.

## Reproducible measurements

Run serially against the configured isolated test database, after preparing its
normal migrations/runtime role:

~~~sh
MIX_ENV=test mix run scripts/benchmark_stage_boards.exs   docs/evidence/demo-readiness/board-discovery-benchmark.json
~~~

The script refuses non-test environments and database names not ending in _test.
Each scenario rolls back its fixtures in a SQL sandbox. It publishes 1/10/100
distinct populated pins with narrow (2 fields) and wide (102 fields) definitions,
uses a separate requester for hidden records, verifies the admitted pin count and
one visible selected card, warms each operation twice and records nine raw samples.
The report fingerprints the measured source files. Fixture creation is outside the
measurements. There is one organization and serial traffic, not cross-tenant load.

The retained legacy-discovery operation reproduces the previous full-definition
lookup and admission; compact discovery measures its replacement. Board refresh
measures the complete current StageBoards read, including authorization, counts,
filters and card projection. It must not be compared as a full old/new board pair.

[Raw data and source fingerprints](evidence/demo-readiness/board-discovery-benchmark.json)
include local runtime details and per-operation samples/p50/p95/p99. Payload is the
size of uncompressed Erlang external-term encoding of decoded database result rows.
It is a reproducible database-result payload proxy, not PostgreSQL wire bytes,
peak application memory or a browser payload. Instrumentation is included in
latency. At nine samples nearest-rank p95 and p99 both equal the maximum; these
are diagnostic observations, not statistical tail/capacity guarantees.

| Shape | Populated pins | Legacy discovery p50 ms | Compact discovery p50 ms | Current refresh p50 ms | Legacy / compact decoded bytes |
|---|---:|---:|---:|---:|---:|
| narrow | 1 | 2.71 | 1.63 | 2.41 | 12,272 / 2,332 |
| narrow | 10 | 3.79 | 2.00 | 2.55 | 51,679 / 8,553 |
| narrow | 100 | 10.41 | 5.85 | 6.43 | 445,744 / 70,743 |
| wide | 1 | 2.88 | 1.34 | 2.24 | 56,642 / 2,333 |
| wide | 10 | 5.00 | 2.36 | 3.47 | 295,903 / 8,553 |
| wide | 100 | 27.17 | 7.22 | 8.42 | 2,695,724 / 70,741 |

## README and current family walkthrough (P3 and working-tree observation)

README now describes completed D01–D04 acceptance, all 29 school cases and the
local synthetic limits. The [setup guide](school-demo.md) and
[current family walkthrough](demo-family-isolation.md) identify the exact serving
cluster and six separate two-student accounts. Browser checks observed Oliveira's
#9/#13, Santos's #10/#14 and denial of a direct foreign-case URL. Tests cover all
six disjoint listings and foreign reads/saves, plus fixture rerun preservation.
The accepted earlier database and its independent process remain recoverable.

## Research recommendations retained as follow-up

This change addresses the concrete P2/P3 findings and the requested board-scale
measurement. It does not claim a new complete D04 video, internet performance,
authenticated k6 editing load, or approval from Professor Ângelo. No message was
sent, and the user's seminar files were not edited.

A subsequent evaluation campaign should pin its committed revision/environment,
retain repeated raw runs, and measure authenticated LiveView edits with business
state checks: same-section conflict/recovery, different-section success, expected
conflicts versus unexpected failures, throughput and per-organization isolation.
An HTTP GET-only script is insufficient. The proposed school video should show
same-section recovery as well as a successful board transition. Historical charts
remain historical, and simulated outbox delivery remains at least once rather than
exactly once. Professor alignment and the author's qualitative validation claims
require their own evidence; this patch does not upgrade them into measured results.

## Validation

- Required instrumented mix precommit: **381 tests, zero failures**, seed 865528,
  169.3 seconds. 1,198 token-age checks, zero invalid results, largest future delta 0 ms.
- Focused board/LiveView/enrollment checks: 19 tests, zero failures (seed 833612).
- Family plus new board-discovery regression: 14 tests, zero failures (seed 352967).
- An earlier full run recorded one PostgreSQL query cancellation during enrollment
  fixture insertion. The focused rerun and final complete suite above passed;
  clock diagnostics were clean in both full runs. No timeout or token gate was weakened.
- Fresh family setup repeated without inventory changes; browser checks described above.
- Benchmark completed all six scenarios with business-state assertions and sandbox rollback.
- git diff --check passed. Existing migration module-redefinition warnings remain.
