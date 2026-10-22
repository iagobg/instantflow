# Sprint 10 generated experiences and recreation evidence

Implementation date: 2026-10-22. This closes the participant preview/message and
curated communication work after the [first reviewed participant slice](participant-pages.md)
and [configured views/finance checkpoint](configured-views-and-finance.md).
The machine-readable completion record is
[sprint10-complete.json](evidence/sprint10-complete.json).

## Authoring and setup

Import a portable definition or start a draft in the common model editor. Map its
symbolic roles, departments and any organization-owned budget accounts locally.
Participant candidate roles determine picker eligibility; they grant no record access.
Create and verify relationships through the record's participant controls after
publication. Copies contain no accounts, relationships, grants, records or local IDs.

The typed editor now includes a communication collection. Each declaration selects
one recipient relationship, up to 20 scalar source fields, explicit internal release
actors and a simulated adapter behavior. The ordinary department-based editor creates
workflow-department release actors; imported assigned-user or assigned-department
actors retain their existing scope when edited. Unknown fields/relationships, file or
directory-reference sources, duplicate keys, external release actors and executable
configuration are rejected at publication. Nested `communication_succeeded` guards
name declared communications. This is a fixed guard, not an expression interpreter.

Participant pages optionally select communication keys in addition to their fields,
documents, actions, history and status. Visibility and audience still intersect the
pinned record/section policies. The preview form selects a symbolic role, stage and
synthetic verified relationship state. It uses the runtime actor, section and transition
policy with explicit synthetic facts, reads no records, and executes no commands.
Preview fields contain only fixed example values. Invalid selections fail closed.
Named assignments are absent in this synthetic scenario; the preview does not pretend
that a role alone grants a confidential assignment.

## Curated release and delivery semantics

`Delivery.Curated` owns release, current eligibility, recipient projections, retry and
explicit result resolution. Catalog validation is pure. LiveViews own forms, streams
and navigation; they do not query the database or decide delivery authority.

Release locks the current tenant authorization gate and ticket, checks the sender's
declared actor and read access to every selected source section, verifies the recipient's
current local membership/candidate eligibility and verified relationship, and fences the
observed ticket revision. It snapshots only selected field labels/values, the pinned
version, communication label, exact recipient and relationship revision. Event, receipt,
ticket revision, refresh intent and durable message commit together under the existing
outbox quota lock. Replaying a receipt requires current authority and the same command
digest. A later source edit or publication cannot rewrite this snapshot. The additive
outbox migration protects release snapshots against updates in PostgreSQL.

Dispatch acquires the same shared authorization gate as commands, before ticket/outbox
locks. Current organization, author membership/release authority, recipient membership,
candidate roles and exact verified relationship revision are checked again. A revoked
queued recipient produces a durable cancelled attempt; the inbox excludes its rows and
counts. Retry and explicit result application perform the same current checks. Permission
changes take the exclusive gate, so they serialize with dispatch rather than racing an
unchecked result application.

Supported adapters are simulated success, fail once, persistent failure and ambiguous
outcome. Failed messages permit at most three dispatch attempts. Ambiguous messages need
an authorized explicit success/failure decision and a nonempty reason; no automatic
success is inferred. Attempts remain immutable. A closure guard requires the **latest**
release for its declared key to have succeeded and remain eligible. Legacy uncurated
notification success cannot satisfy it, and curated success cannot satisfy a legacy
notification-kind guard. Multi-recipient quorum/acknowledgement rules are unsupported;
use separate explicitly named declarations for independently required outcomes.

## Generated routes and bounded reads

All routes are organization-bound and authenticate the current membership:

| Audience | Shared route | Projection |
|---|---|---|
| Staff | `/o/:slug/processos/:workflow_id` | Configured authorized records, finance and operational blocks |
| Staff | `/o/:slug/processos/:workflow_id/registros/:id` | Authorized sections, participant setup and selected release controls |
| Record participants | `/o/:slug/processos/:workflow_id/participacao/:page_key` | Authorized pinned participant list |
| Record participants | `/o/:slug/processos/:workflow_id/participacao/:page_key/registros/:id` | Selected fields/files/actions/status/history/messages |
| Message-only recipients | `/o/:slug/processos/:workflow_id/comunicacoes` | Only their eligible release snapshots and simulated statuses |

Discovery adds inbox entries without requiring creation or internal-record authority.
Message-only recipients receive no staff workspace link or internal record URL. Generic
record delivery collections exclude curated payloads; sender controls and recipient
inboxes are separate projections. No renderer selects behavior by school/example key.

Inbox authorization is in SQL **before** count, ordering and paging. Totals count all
currently eligible releases for that recipient and process, including pending/failed
statuses; source content appears only after success. Ordering is descending immutable
message ID. Pages contain 25 rows with clamped positive page numbers. There is no
per-message read-policy query. A 1-versus-28 release test proves constant query count,
25-row result bounds, complete/disjoint paging, hidden-recipient count isolation and
malformed-page fallback. Participant-page messages additionally constrain ticket and
declared communication keys, with the same 25-row cap; the dedicated inbox provides
history paging.

Release pickers query only current verified eligible recipients, search names on the
server, and return at most 25 choices per declared communication (maximum 20 declarations).
Sender controls fetch at most one latest message per declaration. Assignment pickers now
apply current user/membership, role and department eligibility in SQL before their
100-choice cap and expose server-side name search. Explicit scoped staff grants on
modern parent identities are honored consistently by runtime and SQL assignment policy.
Legacy parent-portal exclusion remains confined to pinned legacy definitions.

Broadcasts contain invalidations, not message content. Inbox and participant LiveViews
reload through current tenant/relationship policy on invalidation, permissions change,
reconcile and reconnect. Protected streams/forms are cleared when access disappears.
Source ticket IDs, sender identities, internal reasons, confidential notes and raw
outbox payload metadata are absent from recipient projections.

## Executable recreation matrix

`Sprint10RecreationFixtures` recreates the four school definitions with independently
renamed workflow, role, section, field, stage, transition, binding and page keys. It
converts guardian authority into declared verified participation, declares private
document policies, configures views/finance and replaces incident-kind closure with a
curated communication guard. The equipment fixture extends the blank service desk
through the same contracts. No new per-example screen or route is introduced.

| Design behavior | Portable fixture and generated route | Named acceptance |
|---|---|---|
| Enrollment: invited family submits and corrects documents; admissions verifies; academic placement; simulated deposit; IT sees minimum identity and retries provisioning | `independent_enrollment`, `copy_family_portal`, shared staff record and inbox | `Sprint10SchoolRecreationTest`: copied enrollment |
| Incident: factual report, triage, named counselor assignment, confidential concurrent section work, resolution and curated-only family communication | `independent_incident`, configured `copy_triage`, shared record/inbox | `Sprint10SchoolRecreationTest`: copied incident |
| Requisition: quantity/cost proposal, academic/finance approval, reservation release and renewed review, order, partial receipt guard and complete receipt | `independent_requisition`, configured board and finance blocks | `Sprint10SchoolRecreationTest`: copied requisition |
| Field trip: itinerary/date/destination/participants/cost/risks, academic/finance review, transport, renewed review after correction, safety and posting | `independent_field_trip`, configured calendar and finance blocks | `Sprint10SchoolRecreationTest`: copied field_trip |
| Equipment: resource session, invited owner correction/private document, parts and captured prices, handoff/settlement, configured view and curated result | blank `equipment_external_desk`, `customer` participant page and shared operational/record routes | `Sprint10EquipmentRecreationTest`: blank equipment desk |
| Core-only process without capability setup | `BuilderFixtures.core_definition`, shared record route | `BuilderRecreationTest`: core-only import |

Each school scenario imports, maps and publishes through the common editor controls,
then saves forms and performs workflow transitions through generated LiveViews.
Relationship/resource/delivery setup may use the existing scoped commands. The equipment
scenario also maps/publishes through the editor and operates participant fields, upload,
resubmission, release and retry through common pages. Existing finance concurrency,
explicit reset/rollback, assignment privacy, private download, cross-tenant/shared-user,
revocation, second-publication and populated migration/restore tests remain regression
gates alongside these recreations. The matrix adds evidence; it does not replace those
stronger context and migration tests with route-presence checks.

## Architecture review and remaining limits

Review corrected message-only workspace discovery, generic curated-payload exposure,
multi-field input IDs, curated retry routing, typed section-editor roundtrips, full
six-capability composition and SQL assignment eligibility before paging. Privacy and
failure behavior are tested with the surfaces rather than deferred to a later sprint.
Portable schema/interchange, local mapping and immutable pinned versions remain the
shared contract; commands reuse existing tenant locks, durable receipts/events/outbox,
finance transactions, document policy and guarded transition execution.

Unsupported here: anonymous signup/uploads, file/directory-reference message sources,
arbitrary expressions/transports, automatic ambiguous-result inference, recipient quorum,
live preview data, payment providers, accounting/tax/currency expansion and detailed trip
consent. Imports with unsupported declarations fail validation instead of publishing
inoperable screens. Delivery is explicitly simulated.

Sprint 11 retains full customer-volume measurement, residual historical load-all read
paths, operational contract extraction, compatibility and populated replacement acceptance.
Historical enrollment/guardian URLs and pinned inferred-reset adapters remain documented
compatibility paths. Existing templates are not silently migrated or installed into
unrelated organizations. This local completion authorizes no deployment or customer launch.

## Architecture review corrections

The [independent review](sprint10-architecture-review.md) reproduced a direct-document
projection bypass and a multiple-select browser-payload failure. The
[resolution](sprint10-review-resolution.md) adds pinned participant release checks at
the download authorization entry point and shared generated-form conversion, with
maintained direct-URL, revocation, pinning, selection/clearing and forged-option tests.
Its evidence supplements the initial completion result without changing Sprint 11 scope.
