# Sprint 11 completion architecture review

Reviewed 2026-10-23 at commit 14160943d1c5960c04878ccde3e858508c969de1.
The working tree was clean at the start. This review builds on the earlier
checkpoint reviews and inspects the subsequent implementation and acceptance
reports rather than treating their completion labels as independent proof.

## Conclusion

Sprint 11 substantially fulfills the intended architecture correction. No new
blocking finding was identified in the reviewed scope. Accept the sprint as the
development architecture gate for Sprint 12, with the measurement and reliability
qualifications below. This is not customer launch approval or proof that arbitrary
future business processes can be generated without new registered capabilities.

The resulting system is a configurable modular monolith: definitions and local
bindings compose shared participant, file, finance, communication and operational
behavior. School examples are installation data and acceptance fixtures rather
than alternate policy/runtime implementations. Restaurant and equipment workflows
exercise the same guarded command, publication and generated-page boundaries.

## Task assessment

| Task | Assessment and evidence |
|---|---|
| T01 operational contracts | Strong fit. Explicit versioned semantics define captured actors, supported manual settlement/payment methods, organization dates and estimated consumption. Existing session commands use pinned business rules plus current grants. Archival preserves unpaid history separately from payment, with resource reuse and replay regressions. Unsupported accounting semantics fail validation. |
| T02 bounded reads and scale | Substantial implementation, with appropriately bounded acceptance. Operations.ReadModel owns stable pages and SQL totals; workspaces and participant/message discovery authorize before paging. The original Projections/PolicyQuery boundary remains shared. Query-local grouping requires matching policy inputs/bindings and keeps actual pins, instead of caching authorization. Read-only connection leasing does not replace fresh context authorization. Retained performance evidence covers the declared synthetic cases; see measurement limits below. |
| T03 contract consistency | Strong improvement. Publication validates dependency/conflict metadata and supported field/surface combinations. Tests exercise all 32 optional-capability subsets, including 24 supported baseline lifecycles, with separate composed-effect rollback tests. Generated forms share controls/conversion; direct document release, recipient eligibility and pinned account/current-grant behavior have negative coverage. The subset test alone is not exhaustive testing of every possible combination of business effects. |
| T04 ownership and maintainability | Fits the modular-monolith goal. AuthoringPanels, FieldInput, PaginationControls and Operations.ReadModel have concrete responsibilities; layouts render supplied navigation rather than query it. Publication owns its invalidation, and retired school contexts/routes are removed. Dependency tests guard important migrated paths. They are useful guardrails, not a complete formal dependency proof; large coordinating LiveViews/contexts still need discipline as features grow. |
| T05 recreation and preservation | Credible, layered evidence. Six independently configured processes coexist in each of two organizations with local mappings and shared-identity denial/revocation. Separate generated-interface lifecycle tests cover school, restaurant and blank equipment scenarios. Supported restoration uses actual pg_dump/pg_restore and full table snapshots; historical migration/restore is covered separately. Coexistence installation alone is correctly not described as full lifecycle proof. |

## Previous findings

The older-session workspace no longer returns unrelated resource occupancy,
sessions or daily reports under an old pin. Its read model is narrowed at the
service boundary, retaining the item-entry catalog required for ongoing work.
The original independent newer-session exclusion probe passes.

Opening receipt replay resolves and authorizes its pinned result before returning
success. The original independent retirement/republication replay probe passes.
The archival migration and maintained populated operational recovery test cover
the previous resource/day-close deadlock; the old probe that only inserts a
classification after migrations is not equivalent to that archival migration.

## Qualifications, not newly reproduced blockers

- The prior intermittent LiveView invalid-session/reload failure remains unexplained.
  The current unmodified precommit run passed without diagnostic instrumentation.
  That does not establish a fix or justify silently retrying future failures. Keep
  the retained failure evidence and investigate recurrence before customer readiness.
- The load/browser reports were inspected, not independently rerun in this review.
  Reported workstation timings are evidence for the declared synthetic workload,
  not production capacity. First application reads follow fixture-warmed storage.
- Sampled caller heap and whole-VM growth divided by concurrency do not prove a
  worst-case individual request allocation bound. Protocol totals/means likewise
  are not per-request maxima. The final acceptance document discloses these limits;
  retain them when describing T02 as complete and remeasure intended infrastructure
  under the later operational acceptance gates.
- Supported and retired historical restoration are separate fixtures/backups.
  This is meaningful preservation evidence, not certification of tenant-selective,
  off-host, encrypted or production recovery objectives.
- Supported semantics remain bounded: manual BRL settlement, estimated product
  consumption, simulated communications and explicit registered capabilities.
  Rentals, stock accounting, payment-provider semantics and arbitrary orchestration
  are not implied by the restaurant/equipment recreations.

## Independent verification

- mix precommit: 346 tests, zero failures, seed 689365; exit code zero.
- Original navigation/replay probes: two tests, zero failures, seed 281599;
  the two obsolete classification-only occupancy probes were excluded.
- git diff --check passed before writing this review.

The full suite includes the maintained field/public-entry matrices, generated
recreation, independent runtime-connection checks and supported/historical
migration/restore tests. Assets, runner/deployment checks and the load/browser
matrix were not separately rerun; their reported results belong to the execution
agent's evidence. No production implementation changed during this review.

The main architectural gain is a consistent supported path from authoring and
publication through authorized reads, commands and generated interfaces. Preserve
that path as new domains arrive: add reusable declarations and capability behavior
with positive and negative scenario tests, rather than routing on example names.
