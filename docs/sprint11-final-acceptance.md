# Sprint 11 consolidated acceptance — 2026-10-23

Status: accepted; Sprint 11 is Done, 5/5 tasks. Implementation checkpoint
7d7b5d8 completes T02; this consolidated report closes T05. All 25 backend cases,
the connected-browser gate, populated restoration, 346-test precommit, production
assets, 17 runner checks and 8 deployment checks pass within the scope below.

## Implementation and authority

Independent definitions now share admission predicates only when their policy
inputs and local bindings are equal. This grouping is query-local: it does not
cache authority. Participant and configured-view discovery starts from published
versions and checks for an authorized record with EXISTS. Curated discovery uses
its separate current recipient/relationship/snapshot boundary. A tenant/recipient/
ticket/message index supports that recipient lookup. Actual pins retain their
stage labels and field schemas; configured record views still load full schemas.
The new DiscoveryPolicyGroupsTest proves independent names, changed local grants,
old pins, relationship revocation and exact counts through public read surfaces.

Earlier checkpoints provide the other parts of T02: authorized SQL pagination,
explicit operation dates and aggregates, compact repeated pinned bodies, one
connection lease around a composite web read, and connected-only initial records.
The lease does not authorize: each context keeps its fresh tenant and grant checks.
List cells preview 80 characters; record detail, private files and curated snapshots
retain full values. Loading placeholders do not count as visible completion.

## Recreation and current buildability

All scenarios use generated organization/process routes, portable definitions and
explicit local mappings. Common recreation has no dependency on retired school
routes, guardian invitation writers or inferred operational contracts.

| Scenario and maintained fixture | Supported authoring/setup | Maintained lifecycle assertions |
|---|---|---|
| Independent enrollment, Sprint10RecreationFixtures.definition(enrollment) | Import; map roles/departments; publish in editor; generic external invitation and verified participant | Family correction, quarantined private files/review, minimum IT projection, simulated delivery failure/retry |
| Independent confidential incident, definition(incident) | Import; map roles/departments; publish; named section assignment | Restricted triage, confidential sections, curated recipient isolation and retry |
| Independent requisition, definition(requisition) | Import; map local roles/departments/budget; publish | Finance guards, renewed review, partial receipt and completion |
| Independent field trip, definition(field_trip) | Import; map local roles/departments/budget; publish | Prerequisites, finance/renewed review and completion; calculations remain simulated/disabled without host acceptance |
| Independent supper room, test/fixtures/sprint11/supper_room.json | Import; map; editor configures operational page, destinations and settlement | Kitchen/Parrilla captured batches, handoff, cash/card/Pix contract, exact day summaries, resource reuse and pinned checkout |
| Blank equipment desk, Sprint10RecreationFixtures.equipment() | Compose literal definition from blank, map/publish in editor; add participant/document/view/communication blocks | Invited correction, parts/reference selection, private document review, views and curated messages |

The definitions live in test/support/sprint10_recreation_fixtures.ex and
sprint11_acceptance_fixtures.ex. Rendered authoring/lifecycle evidence lives in
sprint10_school_recreation_test.exs, sprint10_equipment_recreation_test.exs and
sprint11_operational_authoring_test.exs under test/instantflow_web/live.
Generated editor URLs use /o/:slug/modelos/:draft; generated experiences use
/o/:slug/processos/:workflow, /p/:declared_page and /comunicacoes. No example key
selects a special implementation.

Sprint11CombinedRecreationTest starts without published versions, imports/maps/
publishes all six processes in each of two organizations and checks different
local authority for one global identity, explicit grant/revocation and cross-org
process denial. Separate lifecycle tests exercise the happy/exception paths above;
coexistence installation alone is not represented as complete lifecycle evidence.
The contract/ownership checkpoint records capability combinations, field surfaces,
transaction rollback, duplicate replay and independent-connection races.

## Populated preservation and recovery

Sprint11SupportedRecoveryTest builds a fresh isolated database through supported
imports, mappings and business commands, with only identity/organization bootstrap
as infrastructure fixtures. Both organizations contain all six definitions. A
real pg_dump/pg_restore preserves every public table, supported immutable pins,
relationships, private bytes, finance holds, operational captures, receipts, audit
and outbox intents. An up-to-date migration run preserves row contents. Restored
runtime credentials cannot read unscoped records; authorized opening replay
returns the original receipt/session; day totals remain exact. A supported curated
job fails once and is retried through its authorized owner. Relationship revocation
removes inbox/file access; cross-process and cross-tenant attempts remain denied.

GuardianMigrationTest and OperationalRetirementMigrationTest separately rehearse
the D-32 retained historical set through populated forward migration and restore.
They preserve captured names/prices, paid versus archived-unpaid history, private
files and audit, cancel retired pending jobs with audit, and prove resource reuse.
These are separate backups, not one combined historical/supported snapshot.
All D-32 dispositions are classified from the user's synthetic-only environment
attestation and maintained repository evidence. No serving database was reset,
migrated or deployed during this acceptance.

## Measurement method and limits

The unchanged budgets are 500 ms backend p95 (including every tenant), 1 second
connected browser p95, 32 MiB incremental memory per read, 4 MiB fetched decoded
payload, and 25 output rows. Each backend case starts a fresh application against
its own migrated synthetic database: ten organizations, 10,000 records, 50 readers,
runtime pool ten. Fixture insertion warms PostgreSQL/OS caches; cold means first
application read, not a cold disk. Warm measurement is 1,000 requests per case.
Uneven distribution places 70% of records in one tenant. Full reports retain each
tenant, queries, SQL bytes, fetched rows, decoded JSON/external-term bytes, caller
heap, sampled whole-VM peak, plan diagnostics and pure policy-compilation probes.
Whole-VM growth divided by 50 is an aggregate, not an individual worker maximum;
caller heap at query boundaries is sampled, not a proof about every allocation.
The separate pure compilation probe deliberately compiles every represented pin,
so it is an upper-bound probe rather than the grouped execution compilation count.

Actual PostgreSQL TCP protocol counters cover all database sockets owned by the
benchmark VM, including idle app/operator pools. They report phase totals and
per-request means, not per-request maxima; socket counts must remain stable.
Browser HTTP transfer and incoming WebSocket application-frame bytes are separate
measurements, not decoded SQL payload or Ethernet/TLS packet sizes. Each report
records runtime/DB/scheduler environment, base revision and compiled read-module
fingerprints; evidence manifests record final source hashes.

ANALYZE after bulk fixture creation/restoration is part of readiness, documented
before the accepted repetitions. Earlier unanalysed support failures remain
retained. Other failed policy/browser phases also remain retained; no workload or
numeric budget was lowered after observing failures. Synthetic bulk fixtures
measure read cost; the public recreation/recovery tests prove lifecycle setup.

## Final backend measurements

All 25 cases pass every unchanged gate in both phases, including every tenant.
Worst cold tenant p95 is 277.317 ms; worst warm tenant p95 is 276.726 ms.
Across both phases, maximum sampled caller growth is 9,566,120 bytes and maximum
whole-VM growth divided by 50 is 6,970,713 bytes. Maximum fetched decoded payload
is 1,354,226 bytes. These remain below 32 MiB and 4 MiB respectively, with the
sampling/aggregation limits described above. All protocol-counter phases have
stable nonzero socket counts and valid monotonic byte totals.

| Case | Cold p95 ms | Warm p95 ms | Maximum warm tenant p95 ms |
|---|---:|---:|---:|
| baseline | 114.707 | 66.784 | 67.082 |
| combined | 160.399 | 151.874 | 156.26 |
| hidden-9 | 78.259 | 65.097 | 65.77 |
| hidden-99 | 75.464 | 42.277 | 43.338 |
| idle-processes-10 | 64.092 | 42.443 | 43.116 |
| idle-processes-100 | 51.397 | 32.777 | 34.404 |
| idle-versions-10 | 104.398 | 66.277 | 67.877 |
| idle-versions | 103.392 | 67.534 | 68.904 |
| mixed-versions-10 | 102.084 | 87.653 | 90.075 |
| mixed-versions-100 | 135.401 | 125.71 | 127.332 |
| uneven | 119.701 | 67.525 | 72.287 |
| uneven-mixed-100 | 140.163 | 127.629 | 141.318 |
| width-10 | 107.676 | 67.142 | 67.925 |
| width-50 | 171.341 | 157.477 | 158.334 |
| catalog-wide | 209.86 | 189.622 | 193.38 |
| creation-wide | 196.628 | 196.447 | 196.447 |
| messages-active-pins-100 | 272.178 | 199.703 | 201.455 |
| messages-processes-100 | 195.87 | 120.09 | 123.045 |
| messages-uneven | 165.646 | 136.071 | 139.366 |
| navigation-wide | 99.555 | 73.091 | 74.584 |
| operations-equal | 147.904 | 124.564 | 128.603 |
| operations-uneven | 142.036 | 135.318 | 167.441 |
| participants-active-pins-100 | 272.225 | 225.94 | 226.941 |
| participants-processes-100 | 245.566 | 265.567 | 276.726 |
| participants-uneven | 244.412 | 216.971 | 241.206 |

Full per-tenant reports, exact dimensions, plans and source fingerprints are
retained in [the final evidence](evidence/sprint11-final-acceptance.json), with supporting/browser/intermediate reports in
[evidence/sprint11-admission-scale-checkpoint.json](evidence/sprint11-admission-scale-checkpoint.json).

## Browser gate

Production-digested assets, a loopback disposable endpoint and the Windows in-app
browser ran with 49 backend readers plus the browser reader. The observer waited
for a connected LiveView, actual record count and two animation frames. One cold
reload took 690.6 ms; 100 warm reloads had p95 927.2 ms and maximum 961.4 ms, with
zero failures or samples over one second. Keyboard filtering returned one record
and preserved focus; a real detail reload retained full 1 KiB field values.
Decoded initial HTML was 19,112 bytes, maximum HTTP transfer 4,020 bytes and incoming
WebSocket application frames 163,566 bytes. The background workers completed
173,260 requests at p95 134.319 ms; per-tenant results are retained. This is the
production asset profile on the documented workstation, not a customer network
capacity guarantee. Slower development/production intermediate phases are retained.

## Final verification and handoff

The first final full run had 346 tests and one static architecture-check failure:
it rejected the literal template_key in SQL that discards unused metadata. The
initial exception also mismatched the parameterized SQL placeholder, so a second
run retained that same sole failure. The corrected check now permits only the
exact subtraction while retaining the example-dispatch ban. Product code and
measured workloads did not change. The next untraced full run passed the architecture checks but reproduced the
previous intermittent test-client invalid session in the staff date roundtrip.
The final same-seed precommit passes all 346 tests using the existing numeric-only
age/clock diagnostic, with zero invalid-age events. It captures no tokens/session
contents or verifier arguments and does not change validation. Production assets,
17 calculation-runner checks, 8 deployment checks, Python runner syntax and
whitespace checks pass. The shared component guard also now uses an effective
regex word boundary instead of a literal backspace. No product code changed after
the final measurements. Full reports and failed phases are retained in the linked
evidence; passing diagnostics do not establish the intermittent failure's cause.

Sprints 12–14 remain required before customer activation; S13 retains durable
unsent-draft recovery and physical Windows/POS-80 acceptance. S14 rechecks real-host
capacity, integrations and recovery. Sprint 15 is post-launch observation.

Earlier intermittent LiveView test-client invalid-session observations remain
unexplained. Numeric-only diagnostics did not establish an age-validation failure;
no session tracing, relaxed validation, clock change or automatic retry logic was introduced.
Passing regressions and 101 browser reloads do not establish the original cause.
