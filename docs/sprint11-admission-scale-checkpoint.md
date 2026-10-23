# Sprint 11 admission and browser checkpoint — 2026-10-23

Query-local policy groups now combine independently named processes with equivalent
policy inputs and bindings. Participant/view discovery expands configured pages
once per version and requires an authorized record through EXISTS. Curated inbox
discovery retains its separate current recipient, verified relationship, snapshot
revision and pin eligibility rules, with a tenant/recipient/message read index.
Policy-only reads avoid unused field schemas; configured record views retain them.
No authority is cached across requests. A public regression checks changed role
bindings, old pins, exact discovery counts and live grant/relationship revocation.

The unchanged supporting workload now passes all eleven declared cases, cold and
warm, including every tenant. Participant/message reads cover 100 independent
processes per tenant, 70% uneven record ownership and 100 active publication pins.
Operational equal/uneven reads check complete day aggregates with bounded supporting
pages. Catalog, creation and navigation each cover 100 processes by 100 publications
by 50 fields. All cases retain ten organizations, 10,000 records, 50 readers and
pool ten. No latency, payload, memory or pagination budget changed.

The actual browser gate passes one cold plus 100 warm connected reloads under 49
background readers: cold 690.6 ms, warm p95 927.2 ms, maximum 961.4 ms, zero failures.
Completion includes the actual connected record count and two animation frames.
Keyboard filtering preserves focus; detail reload preserves full 1 KiB values.
Production-digested assets are the acceptance profile; failed development and
production intermediate measurements remain retained. This workstation result is
not a production-host guarantee.

The [evidence](evidence/sprint11-admission-scale-checkpoint.json) retains all support
reports, browser observations, PostgreSQL TCP aggregate counters, compiled module
fingerprints, final source hashes and failed/intermediate participant measurements.
Earlier process-discovery failures were 1,974 ms for participants and pool exhaustion
for messages; grouping alone still failed. Version-first authorized existence and
minimal policy metadata address the supporting-work growth without dropping policy.
The full fourteen-case core matrix also passes against the same read-module
fingerprints. Same-seed precommit passes all 346 tests with the existing numeric-only
age diagnostic (zero invalid-age events); production assets and whitespace pass.
Two static-check failures were corrected with an exact metadata-omission exception
and an effective regex word boundary. An untraced full run also reproduced the
previous intermittent date-field test-client invalid session. It remains
unexplained: the passing diagnostic run does not establish a fix or cause.
No session validation was changed. Consolidated T02/T05 acceptance follows in the
final sprint report.
