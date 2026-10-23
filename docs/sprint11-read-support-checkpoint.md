# Sprint 11 read supporting-volume checkpoint

Started 2026-10-23 on checkpoint-1 revision e07ea2a. This increment addresses
supporting work in the existing authorized projection service. It is an incremental
T02 checkpoint, not full read-scale acceptance.

## Workload fixed before tuning

The existing numeric budgets in design/07-verification.md remain unchanged.
The initial backend comparison uses 10 organizations, 10,000 total tickets,
50 staff/50 concurrent callers and a runtime-role pool of 10. Measure 50 first
projection reads after fixture setup, 100 warmup requests, then 1,000 measured
warm requests (100 per tenant). Each invocation starts a fresh application process
and an isolated migrated database. Fixture insertion warms PostgreSQL/OS caches;
these are not cold-storage results.

Run these cases before and after the change, without a concurrent build/test:
baseline (one version/process, no hidden rows, one selected field); 10 and 100
published primary-process versions with only version 1 referenced; 10 and 100
referenced versions; 10 and 100 installed processes for global view options with
only the primary process holding records; hidden:visible 9:1 and 99:1; selected
width 10 and 50. Each populated field holds 1 KiB long-text within schema limits.
Repeat baseline and 100 referenced versions with an uneven 70%/remaining-nine
record distribution, retaining 50 concurrent callers. Mixed-version rows retain
independent pinned stage labels. Idle definitions deliberately remain installed;
this measures their supporting cost rather than deleting them.

The harness records actual dimensions, verified counts, per-tenant latency,
query count, maximum parameterized SQL bytes, catalog rows/serialized term bytes,
all fetched rows/serialized term bytes and observed caller-heap growth at query
boundaries. These bytes are Erlang external-term sizes, not wire bytes. Query
telemetry includes database execution/pool wait; it does not isolate PostgreSQL
planning or policy compilation. Memory omits pool processes and complete off-heap
BEAM cost. Browser paint/network, full BEAM peak, complete cross-product and
process-catalog creation discovery remain outside this checkpoint. No thresholds
are lowered or full acceptance claimed from these partial measures.

The script creates and retains a new synthetic database and local JSON per case.
It never resets or writes the serving database. Worker execution is disabled;
reads use the actual runtime login and authorization gates. Bulk fixture setup is
privileged and synthetic, not evidence of editor-only recreation.

## Changes and measured result

The same Projections service now loads only versions referenced by tenant-local
tickets. The EXISTS semijoin uses organization/version ownership; it does not
filter or page records ahead of user policy. Referenced historical pins remain
available regardless of the latest publication. Latest workspace definitions for
creation stay in their existing owner. Section/assignment projection predicates
use only versions represented on the selected 25-record page. There is no new
query engine, persisted policy cache or relaxed revocation boundary.

The tenant/version index generated in
20261023040903_index_ticket_policy_version_lookup.exs supports this semijoin.
Before indexing, its actual runtime-role plan scanned all 10,000 tickets, removing
9,000 other-tenant rows in that sample. The indexed plan uses the tenant/version
index instead. Measured planning/execution time for that catalog lookup was
0.457/1.485 ms before indexing and 0.482/0.191 ms after indexing. These are one
lookup's warmed database timings, not complete request or cold-storage evidence.

| Case | Before warm backend p95 ms | Indexed warm backend p95 ms | Catalog rows before → indexed | Maximum SQL bytes before → indexed |
|---|---:|---:|---:|---:|
| Baseline | 33.232 | 35.378 | 1 → 1 | 665 → 665 |
| 100 publications; one pin with records | 181.510 | 36.031 | 100 → 1 | 20079 → 665 |
| 100 installed processes; global view options | 130.920 | 44.087 | 100 → 1 | 23266 → 633 |
| 100 referenced pins | 139.081 | 145.144 | 100 → 100 | 20079 → 20079 |
| 50 selected fields, each 1 KiB | 265.292 | 274.021 | 1 → 1 | 3899 → 3899 |
| Uneven 70% tenant, 100 referenced pins | 143.663 | 150.650 | 100 → 100 | 20079 → 20079 |

Idle-publication fetched row-term bytes fell from 513,730 to 67,148 per request;
empty-process view options fell from 452,729 to 5,850. Every measured tenant's warm
backend p95 in the final 13 cases was below the unchanged 500 ms backend target.
This does not establish the other budgets. The maximum selected width's serialized
fetched terms were 1,321,761 bytes; this is not a wire-payload certification.

Keep the intermediate unindexed phase: its uneven/100-pin p95 rose from 143.663
to 208.979 ms, then measured 150.650 ms with the index. The baseline and 50-field
cases also measured slightly slower in the final run (33.232→35.378 and
265.292→274.021 ms). These are single-run observations; no general speedup is
claimed for active mixed versions or wide values. Maximum SQL for 100 active pins
remains 20,079 bytes. Supporting work is still proportional to referenced pins;
further scale acceptance remains open. No failed timing or target was discarded.

An initial uneven fixture setup exceeded PostgreSQL's 65,535 bind-parameter
limit, before any request timing. The failed setup log was retained; batching
synthetic inserts fixed the runner without reducing its 7,000-record busy tenant,
10,000 total records or concurrency. All three completed phases use the declared
workload.

## Reproduce and regression coverage

With the repository's pinned Elixir/OTP and operator/runtime PostgreSQL roles:

~~~sh
python3 scripts/benchmark_read_matrix.py fresh-label
~~~

The runner refuses to overwrite an existing phase unless --reuse-existing is
explicitly supplied. It records 13 case reports under .local/. Individual cases
use mix run --no-start scripts/benchmark_reads.exs with READ_VERSIONS,
READ_USED_VERSIONS, READ_PROCESSES, READ_HIDDEN, READ_WIDTH, READ_SHAPE,
READ_SURFACE and READ_REPORT. Before measurements require checkpoint-1 revision
e07ea2a's projection implementation; the indexed phase uses this checkpoint.

For the runtime query plan, set READ_EXPLAIN_REPORT to a retained case JSON and
READ_EXPLAIN_OUTPUT to a new local JSON, then run mix run --no-start
scripts/explain_read_lookup.exs. This reuses the retained synthetic database;
it does not mutate business data.

The quantitative regression fails against the previous implementation with
101 fetched catalog rows rather than one. It now proves catalog result rows and
maximum SQL remain unchanged after 100 idle publications and 30 unrelated empty
processes, then creates a new pin and verifies both old/new labels, exact counts,
discovery and current participant revocation. Existing mixed-version, assignment,
filter metadata, hidden-section, direct-access and generated-view tests remain
mandatory in the full precommit gate.

Durable reports retain all tenant summaries and exact dimensions:
[baseline](evidence/sprint11-read-support-before.json),
[query change before indexing](evidence/sprint11-read-support-after.json),
[indexed](evidence/sprint11-read-support-indexed.json) and
[query plans](evidence/sprint11-read-support-query-plans.json).
The [checkpoint evidence](evidence/sprint11-read-support-checkpoint.json) records
source/log hashes and verification.

## Remaining T02 work

Record reads still compile all referenced pins for exact authorized selection,
counts and metadata. Workspaces.installed loads latest definitions for installed
process discovery/creation. Operational workspace/reporting still loads catalog,
resources and day/session line collections for application-side aggregates.
Participant discovery also needs full mixed-version/installed-process acceptance.
These paths and distributions remain in the T02 caller inventory; this increment
does not describe them as bounded merely because one page contains 25 records.

Complete the full read workload and browser latency, all-request planning/policy
compilation, actual fetched-byte and complete BEAM memory/peak evidence before
closing T02. Keep original budgets and retain failed results. T03 contract/public
entry/form matrices, T04 residual cohesion and T05 full recreation remain open.
Sprint status remains In progress, 1/5. The known intermittent LiveView reload is
not established as fixed. No serving migration, deployment or destructive reset
was performed.
