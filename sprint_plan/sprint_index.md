# Sprint progression

[Design index](../design/index.md)

Status: Sprints 00–11 complete; Sprints 12–15 customer delivery planned · Updated: 2026-10-23

Dependency-ordered increments without duration estimates. Sprints 00 and 01 retain their original single-organization evidence. Sprint 01A has migrated and verified the multi-organization foundation before Sprint 02, preserving existing records.

| Sprint | Outcome | Dependencies | Status | Tasks done | Actual start / finish |
|---|---|---|---|---|---|
| [00](sprint_00.md) | Foundation and PT-BR shell | None | Done | 5/5 | 2026-10-20 / 2026-10-20 |
| [01](sprint_01.md) | Versioned workflow runtime | 00; D-08, D-14 | Done | 5/5 | 2026-10-20 / 2026-10-20 |
| [01A](sprint_01a.md) | Multi-organization foundation migration | 01; D-01, D-18–20 | Done | 5/5 | 2026-10-20 / 2026-10-20 |
| [02](sprint_02.md) | Local permissions and concurrent collaboration | 01A; D-13 | Done | 5/5 | 2026-10-20 / 2026-10-20 |
| [03](sprint_03.md) | Editor, interchange, authoring guide | 02; D-15 | Done | 5/5 | 2026-10-20 / 2026-10-20 |
| [04](sprint_04.md) | Enrollment and parent portal | 03; D-05, D-10–12 | Done | 5/5 | 2026-10-20 / 2026-10-21 |
| [05](sprint_05.md) | Budgets, purchasing, field trips | 04; D-07 | Done | 5/5 | 2026-10-21 / 2026-10-21 |
| [06](sprint_06.md) | Confidential incident collaboration | 05; D-06 | Done | 5/5 | 2026-10-21 / 2026-10-21 |
| [07](sprint_07.md) | Integrated demonstration and delivery | 06; D-09 | Done | 5/5 | 2026-10-21 / 2026-10-21 |
| [08](sprint_08.md) | Optional isolated Python calculations | 07; D-16, D-17; host activation gate | Done | 5/5 | 2026-10-21 / 2026-10-21 |
| [09](sprint_09.md) | Shared builder contracts, participants, references and document policies | Existing 01A–08; D-25–28 | Done | 5/5 | 2026-10-21 / 2026-10-21 |
| [10](sprint_10.md) | Generated participant experiences and reusable projections | 09; D-06–07, D-25–27 | Done | 4/4 | 2026-10-22 / 2026-10-22 |
| [11](sprint_11.md) | Cross-domain contracts, scalable reads and builder acceptance | corrected 09–10; D-09, D-14, D-25–30 | Done | 5/5 | 2026-10-22 / 2026-10-23 |
| [12](sprint_12.md) | Pilot scope, isolation and account access | 11 architecture gate; D-21–23, D-27 | Planned | 0/3 | — / — |
| [13](sprint_13.md) | Organization onboarding and first workflow | 12; D-22, D-27 | Planned | 0/3 | — / — |
| [14](sprint_14.md) | Operations, data lifecycle and pilot launch readiness | 13; D-21, D-23 | Planned | 0/3 | — / — |
| [15](sprint_15.md) | Customer pilot evaluation | 14; actual observation period | Planned | 0/1 | — / — |

## Tracking

The [S09–10 legacy inventory](../docs/sprint11-legacy-disposition-inventory.md)
assigns six concrete D-32 dispositions to Sprint 11's existing tasks, including
implicit legacy detection, undeclared document policies and the guardian database
bridge. No additional sprint or task is introduced.

Sprint 11's mid-execution D-32 revision replaces blanket legacy support with an
[evidenced disposition and retirement gate](sprint_11.md#mid-sprint-compatibility-policy--d-32).
The first operational checkpoint is preserved. Synthetic-only paths should be
retired; retained history and active consumers receive only the support their
evidence requires. Supported builder versioning and data integrity remain required.
That revision retained the same five tasks; final acceptance is recorded below.

Sprint 11's [execution checkpoints](sprint_11.md#execution-checkpoints-after-sprints-0910)
incorporate the corrected Sprint 10 review under D-30: early restaurant composition,
public-entry authorization parity, real form-payload coverage and version/process
scale measurements. Existing bounded projections are the baseline. Its five tasks
and feature scope are unchanged. Execution started on 2026-10-22. The [first operational checkpoint](../docs/sprint11-operational-checkpoint.md) records the initial slice; the [retirement checkpoint](../docs/sprint11-retirement-checkpoint.md) completes T01 and the D-32 inventory dispositions, with populated recovery and transferred security/business assertions. Current status is In progress, 3/5; T02 and T05 remain open. The [contract/ownership acceptance](../docs/sprint11-contract-ownership-checkpoint.md) completes T03 and T04.

Sprint 10's [pre-execution sequence and checkpoints](sprint_10.md#execution-order-and-checkpoints)
incorporate the corrected Sprint 09 contracts under D-29. Deliver the first
participant slice with bounded queries before expanding views, finance and
communications. Sprint 10 owns bounded reads for its new/migrated surfaces;
Sprint 11 completes residual paths and load acceptance. The four Sprint 10 task
IDs are unchanged. All four tasks are complete (4/4). Sprint 10 started and finished on
2026-10-22. The [bounded query checkpoint](../docs/bounded-projections.md), reviewed
[participant slice](../docs/participant-pages.md), [view/finance checkpoint](../docs/configured-views-and-finance.md)
and [generated-experience recreation matrix](../docs/sprint10-generated-experiences.md)
record the implementation sequence. Final validation passes 268 tests, asset build
and whitespace checks; [completion evidence](../docs/evidence/sprint10-complete.json)
records the exact sources and logs. The [review correction evidence](../docs/evidence/sprint10-review-resolution.json) supplements that checkpoint: direct-download release and browser multiple-choice corrections pass 273 tests, asset build and whitespace checks. Sprint 11 has since completed T01; its remaining architecture gates are open.

The [builder architecture contract](../docs/builder-architecture-contract.md) and D-28 establish the remediation sequence. Sprint 09 now completes the shared execution/binding boundary, participants, references, document policies and populated migration/recovery with [implementation evidence](../docs/participants-and-documents.md). Sprint 10 introduces bounded projections and explicit correction resets; Sprint 11 completes scale, compatibility and full school replacement. Sprint 11 cleanup does not defer modular design until the end.

Architecture Sprints 09–11 precede pilot feature work, following the [modularity review](../docs/modularity-review.md) and D-25–27. They cover participant/reference/document policies, generated projections and supporting capabilities, operational contracts, scalable reads, maintainable boundaries and complete recreation of the original school examples plus restaurant/non-school processes. The local structural refactor is baseline evidence; remaining tasks stay unchecked until their own acceptance passes.

The preserved first-customer plan moves to Sprints 12–15, coordinated by the [shared roadmap, traceability mapping and activation checklist](first_customer_roadmap.md). Sprint 11 is the architecture prerequisite; Sprints 12–14 gate live pilot activation. Sprint 15 evaluates actual use without keeping completed engineering sprints open. Shared-database controls and academic Python restrictions remain in force. Planning does not authorize deployment or real customer processing.

The user reopened Sprint 08 on 2026-10-21, selected the synthetic trip calculator and explicitly approved gVisor sharing their private Oracle ARM VPS with Phoenix/PostgreSQL. The [readiness assessment](../docs/python-readiness.md) records the revised host boundary and operating defaults. The actual A1 isolation, service recovery and deployed-release application rehearsal passed; execution is enabled in this private deployment, with disabled defaults elsewhere. Sprint 08 is Done. Sprint 08 is a post-proof-of-concept extension, not a requirement for completing Sprints 00–07. Do not add Python execution to the completed Sprint 01 or delay Sprint 02 for it.

Statuses: Planned → Ready → In progress → Review → Done. Blocked requires a concrete blocker and owner in the sprint file.

Check tasks only with evidence. Derive counts from task checkboxes; acceptance criteria are an additional gate. Record actual dates, evidence links, and remaining defects when status changes. Completed task counts alone do not mean Done.

All sprints use [shared completion rules](../design/07-verification.md). Scope changes update this index, the sprint, and the design register.

## Priority reorganization — 2026-10-21

At the user's request, the remaining modularity findings are now explicit higher-priority Sprints 09–11 rather than an informal checkpoint. Previously planned Sprints 09–12 become 12–15 with scope and local evidence preserved; the [roadmap mapping](first_customer_roadmap.md#scope-tracking) resolves older identifiers. Completed Sprints 00–08 are unchanged. No sprint is marked started or complete by this planning update. D-27 records the ordering; the next implementation increment is Sprint 09.

The 2026-10-23 [Sprint 11 checkpoint-review corrections](../docs/sprint11-first-checkpoint-review-resolution.md)
resolve the two reproduced retirement lifecycle gaps with populated operational
migration/restore and generated-page regressions. Sprint 11 remains In progress,
1/5; the wider architecture gate is not closed by this correction.

Sprint 11's next [read-support checkpoint](../docs/sprint11-read-support-checkpoint.md)
measures and removes idle-publication/empty-process overhead from the shared
record query service and adds its tenant/version index. All three measurement
phases are retained. Full T02 scale/browser/BEAM acceptance and T03–T05 remain
open; status stays In progress, 1/5.

Sprint 11's [pinned-navigation checkpoint](../docs/sprint11-pinned-navigation-checkpoint.md)
keeps supported old session URLs and payment rules working after publication
changes while enforcing current grants, process ownership and current-workspace
setup boundaries. This is an incremental T03 checkpoint; status remains In
progress, 1/5.

Three-checkpoint review correction — 2026-10-23: historical operational reads now
return only the authorized session and item-entry catalog, without shared resource
occupancy or daily reports. The
[resolution](../docs/sprint11-three-checkpoints-review-resolution.md) records
current-only session exclusion, rendered item entry/handoff/settlement, revocation
and isolation regressions. T02–T05 remain open; progress stays 1/5, In progress.

Field/surface checkpoint — 2026-10-23: nine scalar types now pass rendered ordinary
and participant form, typed view and immutable-message roundtrips. Shared generated
controls fix missing optional boolean/single-choice clearing; all eleven field
types have synchronized schema/authoring/surface publication checks. The
[matrix and evidence](../docs/sprint11-field-surface-checkpoint.md) record the
bounded T03/T04 scope. Broader T02–T05 gates remain open; progress stays 1/5.

Participant-release checkpoint — 2026-10-23: after field/surface commit a37ca1a,
multiple-page exact-file release now has maintained HTTP/context/UI/query evidence,
including omitted fields, unreadable sections, subject-only identities, scoped
staff grants, live revocation, old/new pins and cross-process/tenant denial. The
[release matrix](../docs/sprint11-participant-release-checkpoint.md) preserves the
independent curated-recipient boundary. No policy implementation change was needed.
Remaining T02–T05 gates stay open; progress is 1/5, In progress.

Operational read checkpoint — 2026-10-23: interactive catalog/resources, session
batches and consumption now have explicit stable pages; full-day values aggregate
in SQL without per-session query growth. Complete closure snapshots remain stored.
The [read checkpoint](../docs/sprint11-operational-read-checkpoint.md) records later-page
selection/printing, cart retention, row/query bounds and bigint monetary checks.
T02 full discovery/load/browser/VM evidence and remaining T03–T05 work stay open.

Discovery checkpoint — 2026-10-23: process/creation selection now authorizes before
SQL pages; direct workspace lookup and navigation no longer reload every installed
definition. Existing Projections owns bounded participant/view option pages, and
curated discovery prunes unused message versions. The
[discovery report](../docs/sprint11-discovery-checkpoint.md) records later-page
interaction, current-grant/pinned-history parity, pure layout ownership and atomic
publication invalidation. Final T02 measurements and remaining T03–T05 work stay open.

Sprint 11 complete — 2026-10-23: all 5/5 tasks pass the
[consolidated architecture acceptance](../docs/sprint11-final-acceptance.md).
Checkpoint 7d7b5d8 completes bounded participant/message discovery. All 25 backend
cases, connected-browser completion, supported/historical restoration and 346-test
precommit pass; assets and runner/deployment checks pass. The intermittent
test-client invalid-session observation remains documented and unexplained.
Next is Sprint 12; customer activation still requires Sprints 12–14, with Sprint 15
reserved for actual post-launch observation.
