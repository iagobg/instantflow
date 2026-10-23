# Local performance evidence — 2026-10-21

The synthetic demonstration met the adopted local targets for each school: p95 accepted command response at most 500 ms and committed-state visibility at most 1,000 ms. These are backend measurements on one WSL workstation, including connection-pool wait, rather than hosted service objectives.

## Environment and workload

WSL2 Linux 6.18.54.1-microsoft-standard-WSL2, Intel Core i7-13700KF, 24 online Erlang schedulers, 32,768,996 KiB available guest memory, PostgreSQL 16.15, OTP 28 / Elixir 1.19.5. PostgreSQL and Phoenix run on the same workstation; the runtime-role pool has 10 connections. No heavy build or test suite ran concurrently with the final load runs.

The generated database contains 10 organizations, 10,000 tickets and 50 local staff, verified by queries. Each school has 700 requisitions and 100 each of trips, enrollments and incidents. Five concurrent actors per school execute guarded requisition commands with separate requesters/reviewers: save proposal, submit, academic approval, finance reserve, save order reference, order/post, receive and finish. Equal load executes 500 complete lifecycles (4,000 commands); uneven load executes 650 (5,200 commands), with school 1 doing four times as many cycles per actor. Fixtures use synthetic bulk-created initial stages; measured business mutations use the actual non-owner runtime role and application guards.

Command timing includes authorization, locks, guarded writes and pool wait. Visibility measures from the final guarded command returning after commit to PubSub invalidation and an authorized requery using the actual bounded dispatcher and configured polling cadence. There is one final-state observation per lifecycle (500 equal / 650 uneven), repeated across its eight command rows in the JSON; equal weighting leaves its percentile unchanged. It does not measure every intermediate screen state, browser paint, websocket/network delay or a real external provider. Search is measured separately. The mixed workload exercises a full finance lifecycle; it is not a uniform load test of all four templates or arbitrary customer definitions.

## Results and observed fixes

| Profile | Commands | Command p95 ms | Visibility p95 ms | Outcome |
|---|---:|---:|---:|---|
| [Initial simple saves](evidence/sprint07-baseline.json), 1,000 ms poll / pool 50 | 500 | 54.273 | 1,312 | Visibility failed |
| [Simple saves](evidence/sprint07-load.json), 250 ms poll / pool 10 | 500 | 48.975 | 550 | Passed |
| [Uneven simple saves](evidence/sprint07-uneven.json) | 650 | 49.017 | 554 | Passed |
| [Mixed lifecycle before batching](evidence/sprint07-mixed-baseline.json) | 4,000 | 38.913 | 2,258 | Visibility failed |
| [Mixed lifecycle after batching](evidence/sprint07-mixed-load.json) | 4,000 | 39.522 | 830 | Passed |
| [Uneven mixed lifecycle after batching](evidence/sprint07-mixed-uneven.json) | 5,200 | 40.481 | 817 | Passed |

Reducing the poll to 250 ms addressed polling latency. Full lifecycles then exposed repeated refresh work. The dispatcher now locks tickets in stable order, coalesces ordinary business invalidations by a durable ticket revision checkpoint, and commits one bounded tenant batch with an immutable attempt for every selected intent. The bound remains 20 intents per organization per pass. Simulation outcomes always invalidate, even without a new ticket revision. Checkpoint and attempts roll back together, so an uncommitted broadcast can safely retry. Regression tests prove burst handling, rollback/retry and unchanged-revision outcome notifications.

Final uneven-load per-school measurements:

| School | Command p95 ms | Visibility p95 ms |
|---|---:|---:|
| 1 | 31.435 | 792 |
| 2 | 42.675 | 761 |
| 3 | 39.677 | 722 |
| 4 | 39.323 | 703 |
| 5 | 39.982 | 681 |
| 6 | 39.836 | 688 |
| 7 | 43.119 | 712 |
| 8 | 43.228 | 757 |
| 9 | 43.859 | 805 |
| 10 | 44.168 | 864 |

Every measured operation in every school was below 500 ms. Uneven-load aggregate search p95 was 45.611 ms. The raw JSON retains per-operation and per-school values, row counts, configuration and limitations. Fairness evidence combines this uneven load with quota/flooding and independent-connection tenant tests; these short runs do not establish unlimited sustained capacity or protection from every workload.

## Reproduce

Use the pinned runtime and PostgreSQL with operator credentials, then run:

~~~sh
BENCHMARK_MIXED=true BENCHMARK_ENFORCE=true mix run --no-start scripts/benchmark.exs
BENCHMARK_MIXED=true BENCHMARK_UNEVEN=true BENCHMARK_ENFORCE=true mix run --no-start scripts/benchmark.exs
~~~

The harness creates a new database, migrates it, installs synthetic organizations/templates and runs through the runtime role. It retains the generated database and writes .local/benchmark.json unless BENCHMARK_REPORT selects another local report path. It does not reset the serving database. PostgreSQL client tools must be available on PATH or PG_BIN; an extracted local distribution may additionally need LD_LIBRARY_PATH. Operator permissions must allow isolated database creation. BENCHMARK_POOL_SIZE and BENCHMARK_POLL_MS allow explicit pool/poll comparisons.

CI runs the mixed harness without enforcing workstation-specific timing thresholds. Rerun enforced measurements on the intended infrastructure, including real network and browser observations, before accepting production objectives. Connected clients also reconcile missed events every 30 seconds; fault tests verify this recovery path independently of these latency samples.

## Sprint 11 read and browser acceptance — 2026-10-23

The [consolidated read report](sprint11-final-acceptance.md) adds supporting-volume
measurements to the command/update evidence above: cold/warm per-tenant selection,
100 active pins, 100 processes, hidden:visible ratios, 50 selected fields, operation
aggregates, participant/messages and wide catalog/creation/navigation. The fixed
workload remains ten organizations, 10,000 records, 50 readers and runtime pool ten.
Use python3 scripts/benchmark_acceptance_matrix.py UNIQUE_PHASE to reproduce all
25 cases serially with the pinned Mix runtime, PostgreSQL tools and ss available.
The runner refuses to overwrite retained evidence and checks the original budgets.
Each case creates a fresh disposable database; it never resets the serving DB.

The browser uses production-digested assets and counts actual connected records
plus two animation frames. Under 49 background readers its 100 warm reloads have
p95 927.2 ms. Browser HTTP/WebSocket observations, PostgreSQL TCP phase totals and
decoded SQL payload maxima are distinct. Fresh application reads use fixture-warmed
PostgreSQL/OS caches. Bulk fixture/restore readiness includes ANALYZE. Full reports
retain failed phases, source fingerprints and measurement limitations.
