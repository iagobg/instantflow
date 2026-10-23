# Sprint 11 read optimization and supported recovery checkpoint

Executed 2026-10-23 on 8c663b4. Full precommit passes 345 tests, seed 241881;
assets, whitespace, runner and deployment checks pass. Sprint remains 3/5:
T02 still requires the final browser/participant/message measurement gate; T05
will close with that final evidence and the consolidated acceptance matrix.

## Pinned reads and real browser work

The declared combined workload initially failed at 1,683 ms backend p95 and
35,390,016 bytes observed caller heap growth. It retains 10,000 tickets, ten
tenants, fifty simultaneous readers, pool ten, 100 processes, 100 publications,
100 active pins, 99 hidden records per visible and fifty selected 1KiB fields,
with 70% of tickets in one tenant. No target or workload dimension was reduced.

View admission now compiles a section permission once per selected section.
Identical declarations/bindings share a predicate within each fresh read. SQL
fetches an identical immutable body once with each actual pin's stage descriptors;
rendering retains its own labels and all actual pin IDs. Current memberships,
grants and record predicates remain fresh. This is query-local grouping, without
a cross-request authority or definition cache. The unchanged combined case is
140 ms backend p95 and about 2.8 MiB caller heap growth. All fourteen declared
cases, SQL plans, pure policy probes, tenant results, payload and full VM samples
are retained in the [evidence](evidence/sprint11-scale-recovery-checkpoint.json).
Erlang term bytes, decoded row JSON bytes and browser protocol observations are
distinct measurements; none is substituted silently for another.

Historical participant/message classification now uses the equivalent JSON-path
existence predicate with an additive partial index. Operational day, line/batch
joins and ordered catalog pages receive additive indexes. No serving database
migration was run. The initial unanalysed operational bulk fixtures exhausted the
pool; logs are retained. Explicit fixture readiness now includes ANALYZE after
bulk insertion. Equal/uneven workspace-plus-visit runs pass at 258/208 ms warm p95,
checking exact day totals, 1,000 products/resources per tenant and stable 25-row
supporting pages. A restored/bulk-imported database must establish planner
statistics before admitting traffic; these results do not promise cold empty
planner readiness immediately after a bulk load.

The actual browser exposed costs missed by a single backend query. Router and
LiveView composite reads now lease a connection across their context calls;
every context still owns and performs its authorization transaction. Process
parameter validation runs freshly within the projection lease. Operational dates
are fetched only for operational pages. An ordinary generated list shows an
explicit loading state during initial HTML and fetches its authorized data once
when connected. Text list previews are explicitly capped at 80 characters with
full record links. Full typed values remain in detail and curated snapshots;
Unicode detail/readback coverage verifies that the preview does not alter storage.
The full backend workload still fetches all fifty selected 1KiB values.

Failed development and production browser phases remain retained. The final
100-reload acceptance is pending; neither a loading shell nor HTTP response time
is counted as completion. The observer waits for the connected record count and
two animation frames. It records numeric timings and received byte counts only.

## Empty organizations and supported-data restoration

Sprint11CombinedRecreationTest starts with no published processes and installs
all four school copies, an independently keyed supper-room process and the blank
built equipment desk through import, rendered local mapping and publication.
It repeats all six in a second organization. One global identity has different
local authority: the second organization needs an explicit operations grant,
revocation removes discovery, and a first-organization process cannot be created
through the second scope. Existing school/equipment/operational tests retain their
full role-specific happy and exception paths; installation coexistence does not
substitute for those lifecycle tests.

Sprint11SupportedRecoveryTest starts a new empty isolated database and uses public
imports, mappings and business commands. Identity/organization bootstrap rows are
infrastructure fixtures; business models, invitations, relationships, private
uploads/review, finance effects, operations and curated releases use their supported
owners. Both organizations contain all six independent processes. The snapshot
contains all 41 public tables, twelve immutable versions, six actual records, two
verified relationships/private files/finance holds, four captured operational
lines, four sessions, command/operation receipts, audit and 32 outbox intents.

An up-to-date populated migration run changes no rows. A real pg_dump/pg_restore
roundtrip preserves every table exactly, including private bytes and pin metadata.
The restored runtime login sees no unscoped tickets. Current grants and exact
process/tenant ownership still gate reads. Supported opening replay returns the
same captured session. Day sales remain exact; two configured destinations remain
captured. Supported curated jobs are retained, fail once, and require authorized
retry after restore. Relationship revocation then removes file/inbox access.

The separately maintained GuardianMigrationTest and OperationalRetirementMigrationTest
cover the D-32 retained set across populated forward migration and restoration,
including cancelled retired jobs with audit, private history, archived unpaid
versus paid sessions, captured names/prices and resource reuse. This checkpoint
does not claim one backup combines supported and historical fixtures. Its
forward-only assertion now targets the retirement migration explicitly, allowing
later reversible index migrations without weakening retirement preservation.

## Validation limits

The first 345-test run exposed that stale migration-test assumption and one
intermittent test-client invalid session. The same-seed numeric-only diagnostic
run reproduced only the migration assertion, with zero age-invalid events. After
the assertion fix, the same-seed full run passes all 345 tests with zero clock
events. No token/session/signature tracing, validation relaxation or retry logic
was added. The earlier intermittent observation remains unexplained; this result
does not establish its cause or resolution.

Synthetic recreation does not close Sprints 12–14, durable unsent drafts,
physical Windows/POS-80 acceptance, real integrations or customer launch readiness.
