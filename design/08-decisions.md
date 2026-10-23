# Decision register

[Design index](index.md)

| ID | Status | Question / decision | Direction | Needed by |
|---|---|---|---|---|
| D-01 | Confirmed — supersedes earlier scope | Organization scope | Multiple isolated organizations from this development round; migrate existing foundation | Sprint 01A |
| D-02 | Confirmed | Customization | Administrator constrained visual editor | Editor |
| D-03 | Confirmed | Integrations | Explicit demo payments/notifications/provisioning | First slice |
| D-04 | Confirmed | Language and stack | PT-BR; Elixir/Phoenix LiveView; non-authoritative JS | Foundation |
| D-05 | Adopted for synthetic demonstration — 2026-10-21 | Guardian verification | Staff invitation and separate manual verification; independent multiple guardians | Sprint 04 |
| D-06 | Adopted for synthetic demonstration — 2026-10-21 | Incident/support visibility | Named counselor-private notes; dean-only discipline and curated simulated guardian communication | Sprint 06 |
| D-07 | Adopted for synthetic demonstration — 2026-10-21 | Budget/cancellation/price changes | Reserve at finance approval; post at order (trip final approval); full audited reversal; changes restart review | Sprint 05 |
| D-08 | Adopted for implementation | Parallel branches now? | Sequential stages, independent sections | Sprint 01 |
| D-09 | Adopted for synthetic demonstration — 2026-10-21 | Hosting/load/timezone | Local shared deployment; 10 organizations, 50 concurrent staff/10,000 tickets; per-organization timezone default America/Sao_Paulo; production host remains separate | Sprint 07 |
| D-10 | Adopted for synthetic demonstration — 2026-10-21 | Parent self-registration? | Invitations only; no anonymous uploads | Sprint 04 |
| D-11 | Adopted for synthetic demonstration — 2026-10-21 | Parent-visible status/messages | Explicit allowlisted public projection; no internal runtime/history access | Sprint 04 |
| D-12 | Adopted for synthetic demonstration — 2026-10-21 | File types/sizes/retention | Private PDF/PNG/JPEG ≤ 5 MiB, 20 active files/ticket; quarantine/manual release, 30-day synthetic retention | Sprint 04 |
| D-13 | Adopted for implementation | Self-approval | Prohibit finance-sensitive self-approval, including overlapping local roles; no override in this increment | Sprint 02 |
| D-14 | Adopted for implementation | Definition changes | Immutable versions; existing tickets pinned | Sprint 01 |
| D-15 | Confirmed — 2026-10-20 | Interchange and LLM guide | Versioned JSON, draft-only imports, local mappings, shared validation; external LLM authorship | Sprint 03 |
| D-16 | Implemented and verified — 2026-10-21 | Uploaded Python | Async calculations, declared inputs/outputs, reviewed immutable versions; real A1 acceptance passed, private demo enabled | Sprint 08 |
| D-17 | Target-host activation verified — 2026-10-21 | Scripting use case and host boundary | Synthetic trip quote; same Oracle A1 VM with gVisor by explicit user choice; owner-operated demo, no extra infrastructure | Sprint 08 activation |
| D-18 | Adopted for implementation | Tenant persistence/isolation | Shared schema, mandatory tenant scopes, composite ownership FKs, runtime-role RLS; no cross-organization records | Sprint 01A |
| D-19 | Adopted for implementation | Users and organization selection | Global login identity; independent local memberships; organization in route/tab context; no cross-tenant role inheritance | Sprint 01A |
| D-20 | Adopted for implementation | Organization lifecycle and administration | Operator-managed provisioning/suspension; organization-local administrators; no default support data access, billing, signup, or deletion | Sprint 01A |
| D-21 | Proposed for customer pilot — 2026-10-21 | Demo and customers in shared storage | Retain shared-schema database; enforce demo-only identities, simulated effects, scoped reset and resource limits; tests/restores remain isolated | Sprint 12 T02; Sprint 14 T01 |
| D-22 | Proposed for customer pilot — 2026-10-21 | Assisted onboarding and real delivery | Operator provisioning plus resumable organization wizard; one validated workflow; real access/workflow notifications only for eligible customer operations | Sprint 12 T01/T03; Sprint 13 |
| D-23 | Proposed customer activation gate — 2026-10-21 | Academic scope versus real customer operation | Disable/drain uploaded-code execution on customer host unless separately reassessed; require access, backup, data handling and acceptance evidence | Sprint 12 T02; Sprint 14 |

| D-27 | Confirmed priority; implementation planned — 2026-10-21 | Architecture before pilot feature expansion | Prioritize participant/reference/document contracts, generated projections/capabilities, operational contracts, bounded reads and full builder recreation in Sprints 09–11; preserve and renumber unstarted pilot scope to 12–15 | Sprints 09–15 |

## First customer planning — 2026-10-21

Historical numbering: this section records the earlier planning sequence. D-27 below supersedes its priority and numbering; the [roadmap mapping](../sprint_plan/first_customer_roadmap.md#scope-tracking) maps the preserved pilot tasks to Sprints 12–15.

The user requested a plan for essential first-customer changes and asked whether demo and customers can share a database. The [first-customer roadmap](../sprint_plan/first_customer_roadmap.md) and Sprints 09–12 record proposed defaults, not newly implemented guarantees or permission to launch. D-18 already supports shared-schema tenants; credentials alone do not establish isolation, and resource/recovery failure domains remain shared. A demo organization is distinct from a staging/test environment.

D-22 proposes extending the synthetic-only D-03 delivery boundary for explicitly eligible customer operations while retaining simulations for demo/sample records. Initial organization provisioning remains operator-controlled under D-20. D-23 does not undo the completed academic Sprint 08; its accepted same-host risk does not automatically apply to real customer data. Customer workflow, provider, operating terms and measurable targets remain inputs to resolve during implementation. The restaurant is a discovery candidate only.

The phases were split on 2026-10-21 following the user's feedback: Sprint 09 owns scope/isolation/access, Sprint 10 owns onboarding and workflow delivery, Sprint 11 owns operational/customer acceptance, and Sprint 12 owns post-launch evaluation. Scope and shared activation requirements are preserved. Access-message transport belongs to Sprint 09 so account recovery does not depend on later workflow notifications. Each engineering sprint can close on its own evidence; the pilot observation period belongs only to Sprint 12.

## Recorded answers — 2026-10-20

The user initially chose one organization, a visual editor, and explicit simulations. The later explicit request for a multi-organizational platform supersedes the first choice only. The visual editor and simulations remain confirmed. During Sprint 03 implementation, the user explicitly confirmed: “Include import/export and the guide.” D-15 is confirmed.

## Scope revision — multiple organizations, 2026-10-20

D-01 is now multi-organizational by explicit user instruction. D-18–20 document proposed implementation defaults, not additional answers supplied by the user. Add Sprint 01A before Sprint 02 to remove hardcoded organization 1, migrate ownership constraints, separate login from tenant scope, and prove isolation. Completed Sprints 00/01 retain their original evidence; they do not demonstrate the new scope. Detailed contract: [organization isolation](11-organizations.md). No application migration is performed by this documentation change.

Resolve guardian access/confidentiality first, budget semantics before finance, and hosting/load before delivery. Record future rationale here and update affected design/sprint criteria together.

## Implementation defaults — 2026-10-20

After Sprint 01, the user requested a judgment on customer Python and authorized plan changes only if appropriate. D-16 records the recommendation: design the boundary now, deliver the four school slices first, and gate execution behind a separate Sprint 08. This does not reopen completed sprints or claim sandbox security is implemented. D-17 remains unresolved; no runner technology has been selected.

Under the user's authorization to implement and continue the development plan, D-08 uses sequential stages with independent section revisions; parallel branches remain deferred. D-14 uses immutable published versions and pinned tickets, enforced by runtime commands and database immutability triggers. These follow the proposed direction and are recorded as implementation choices, not as separately supplied product answers. Any later change requires a new design decision and migration plan.

## Sprint 01A implementation — 2026-10-20

Following authorization to continue from Sprint 01A, D-18–20 are adopted without deviations: shared-schema RLS with composite ownership constraints, global login/local memberships and route-bound organization selection, and operator-managed provisioning/suspension. The forward migration and isolation/recovery evidence are recorded in Sprint 01A. Python execution remains gated in Sprint 08; no runner or script execution was added.

## Sprint 02 implementation — 2026-10-20

Under the user's authorization to continue the development plan, D-13 adopts the proposed prohibition: a transition explicitly marked finance_sensitive cannot be executed by its requester, regardless of overlapping local profiles. No administrative override is implemented. This is an implementation default following the proposed direction, not a separately supplied product answer. Local grants bind each role to its department; administration never implicitly bypasses record policy. Existing pinned definitions retain their original explicit requester prohibitions. Actor-restricted transition history can exclude confidential reasons and delivery intents from other participants. See the [Sprint 02 evidence](../sprint_plan/sprint_02.md) and [operating notes](../docs/collaboration.md).

## Sprint 04 implementation — 2026-10-21

Under the user's authorization to continue after Sprint 03, D-05 and D-10–12 adopt the proposed direction for synthetic demonstration data. These are implementation defaults, not separately supplied product answers. Staff invite an account to a specific local enrollment, then manually verify each guardian link. Existing-account acceptance proves the same logged-in identity and never upgrades an existing membership. Parents receive only the dedicated enrollment projection, curated public text and authorized application documents; matching names or school membership cannot create a family relationship.

Files are stored privately in tenant-owned PostgreSQL bytea rows, never the static tree. The default is PDF/PNG/JPEG, 5 MiB per file, 20 ready/quarantined objects per ticket and 30 days of demonstration retention. Magic/structure checks, digest verification and a separate staff release gate are implemented. This is not antivirus scanning, proof of document authenticity, or a production retention policy. Expired objects immediately fail download/guard checks; active-tenant polling clears retained content. Suspended tenants and backups require operator retention handling. Real student data, guardian disputes, production malware scanning and retention ownership still require a separate readiness decision.

The template uses additive validated format-1.0 vocabulary (`guardian`, `workflow_department`, transition `department_binding`, `simulate_payment`). No directory lookup, Python execution or real provider call is introduced. See [Sprint 04 evidence](../sprint_plan/sprint_04.md) and [operating notes](../docs/enrollment.md).

## Sprint 05 implementation — 2026-10-21

Under authorization to develop Sprint 05, D-07 adopts the proposed accounting direction as an implementation default, not a separately supplied product answer. Available BRL cents equal allocation minus reservations minus posted spending. Finance reserves; purchasing posts at order; trips post at final safety approval after transport is recorded. Pre-order cancellation releases once. Revised proposals release and repeat all approvals, clearing downstream work. Post-order cancellation requires a separately privileged, reasoned full reversal attesting a fictional credit. Allocation and reversal permissions are distinct from finance approval; no finance-sensitive self-approval bypass exists.

Each requisition tracks one quantified item or homogeneous group with cumulative receiving; heterogeneous units use separate requests. Partial credits/settlements, tax, stock, provider booking and post-order price amendments remain outside the demonstration. Calendar views are date-only agendas, scoped/paginated with explicit stage labels; assignment views report current department and boards report scoped bottlenecks. See [finance operating notes](../docs/finance.md) and [Sprint 05 evidence](../sprint_plan/sprint_05.md).

## Sprint 06 implementation — 2026-10-21

Under authorization to continue the sprint plans, D-06 adopts the proposed confidentiality direction as an implementation default. Support access requires a named local counselor assignment plus current role/department grants; administration and dean privileges alone cannot read support notes/files. The dean edits separate disciplinary and curated communication sections. Parents receive no internal incident projection; the guardian contact/message and delivery remain explicit simulations, with no copied notes or outbound provider call. Named assignment changes/revocations serialize against reads/saves through the exclusive authorization gate. See [incident operating notes](../docs/incidents.md) and [Sprint 06 evidence](../sprint_plan/sprint_06.md).

## Sprint 07 delivery and Sprint 08 hold — 2026-10-21

Under authorization to continue the sprint plan, D-09 adopts the proposed scale/timezone and shared architecture for local synthetic measurement. Equal and uneven full-lifecycle runs meet the local command/visibility targets per organization after measured polling and refresh batching fixes. Production infrastructure and recovery objectives remain operator decisions; these measurements do not confirm them. See [performance evidence](../docs/performance.md) and [release gates](../docs/release-gates.md).

The user explicitly answered “Keep Sprint 8 gated” when asked for its concrete calculation, isolated host and operating/security owner. D-17 remains open. No runner is selected or customer Python executed. Sprint 08 stays Proposed / gated with 0/5 implementation tasks; readiness requires the use case, host, cost/data boundary, patch/security owner and recovery/kill-switch procedure. The completed Sprints 00–07 do not depend on that optional extension.

## Sprint 08 readiness resumed — 2026-10-21

The user subsequently requested Sprint 08 development and selected the field-trip cost calculator with synthetic data. This supersedes the earlier hold and starts S08-T01 assessment. D-17 remains open because separate execution hosting, cost acceptance and operating/security ownership are unresolved. The [readiness assessment](../docs/python-readiness.md) proposes the calculation contract, threat model and recovery procedure; runtime implementation remains gated. No isolated runtime, measured containment, customer tariff or execution capability is claimed.

The user clarified that deployment will be a private university project on their VPS, accessible only with credentials they hold, without real-world clients. They explicitly selected uploaded Python scripts with the original isolation requirements. Synthetic tariff fixtures satisfy the demonstration use case; a real customer is not required. D-17 now concerns VPS compatibility with that isolation boundary and operating arrangements, rather than identifying a client. No additional paid infrastructure or relaxation of the uploaded-code boundary is authorized by this clarification.

The user supplied Oracle Ampere A1 ARM / Ubuntu / 4 OCPUs / 24 GB RAM, shared with Phoenix/PostgreSQL. Official gVisor documentation supports evaluating ARM64 with `systrap`; Firecracker requires unverified KVM access. The [hosting assessment](../docs/python-readiness.md#oracle-a1-assessment--2026-10-21) proposes a separate runner VM to preserve the retained boundary. Using gVisor on the existing application VM instead would be a scope revision requiring the user's decision; it is not implicitly authorized by the hardware specification. D-17 remains open; no remote changes were made.

## Sprint 08 academic implementation — 2026-10-21

The user explicitly chose “Same VPS with gVisor; revise the host-separation requirement for the university demo.” This supersedes the earlier separate-VM assessment and resolves D-17's design direction. gVisor/runsc with systrap is the implementation target on the shared Oracle ARM VM; a successful escape could reach Phoenix/PostgreSQL. Synthetic data, privately gated access, separate OS accounts, no Phoenix Docker authority and disabled-by-default execution define the approved scope.

The single project owner is the operating default under the supplied runbook; no additional paid infrastructure is introduced. The catalogue, independent grants, workflow references, durable runs/fences, asynchronous workers, result guards and PT-BR UX are implemented. Source/fixtures and identity are immutable; runtime results revalidate tenant/actor/stage/input/script/global generations. The [operator guide](../docs/python-calculations.md) and [local evidence](../docs/evidence/sprint08-local.json) distinguish application/controller tests from actual host containment. S08-T03/T05 are complete: real ARM64 runsc isolation, hostile-workload limits/denial, emergency shutdown, broker/watchdog/startup cleanup and deployed-release worker lease/fence recovery passed. The private VPS deployment is enabled through an authenticated Unix socket; no owner database credentials or Docker socket enter Phoenix. Evidence and residual risks are in the [readiness assessment](../docs/python-readiness.md). Development now uses a local branch, verified local merge to main, push and GitHub Actions deployment.

### D-24 — Catalog/resource operational workspace (2026-10-21)

Accepted for a local synthetic restaurant pilot increment: reusable organization-owned products, resource visits, immutable line snapshots, destination batches and daily summaries, presented through a fast-entry operational view. Each visit remains linked to a version-pinned workflow ticket; checkout commits its state transition atomically and cannot be bypassed through a generic transition. Item/printing commands use their own append-only audit receipts. No new restaurant-specific form types or arbitrary template effects are introduced. Initial operators are local administrators. See [architecture and explicit limits](../docs/restaurant-pilot.md). Browser/Windows USB POS-80 printing requires physical acceptance. Inventory is estimated product-unit consumption only. Sprints 09–11 customer activation gates remain in force.

### D-25 — Organization-owned processes generate their interface (2026-10-21)

The user clarified that process definitions must own their URLs and UI; school and restaurant examples are populated definitions, not runtime screen families. The main product now renders interface.pages and their ordered reusable blocks through one generic ProcessLive and the common record editor. No enrollment/incident/restaurant key chooses a generated screen. The authoring UI configures pages, component order, terminology, closing transition and symbolic block access; the normal schema/import/export/publication path carries that declaration. Operational catalogs/resources/visits/reports are isolated by workflow within the organization. Existing publications and rows are preserved by a forward migration. Legacy specialized guardian/document/finance adapters remain compatibility paths with explicit migration limits; they are not represented as fully generalized already. See docs/process-composition.md.

### D-26 — Modularity review before further feature sprints (2026-10-21)

The user requested a standardization, modularity and maintainability pass before continuing the current feature plan, reaffirming that the original projects and later restaurant use cases must be expressible through the process builder. The pass centralizes additive capability and pure interface contracts, separates reusable templates from LiveView orchestration and isolates legacy route discovery. Tests cover renamed lifecycles, pinned publication versions and finance/resource-session composition. The review explicitly retains the remaining participant, external projection, document and specialized dashboard dependencies as architecture prerequisites; passing legacy tests does not prove editor-only recreation. See [review, buildability matrix and extension rules](../docs/modularity-review.md). No customer launch or feature-sprint completion is inferred from this refactor.

### D-27 — Prioritize modular-builder remediation in the sprint plan (2026-10-21)

The user explicitly requested that remaining modularity work be written into the existing sprint format, reorganized and raised in priority. Sprints 09–11 now own the architecture prerequisites: reusable participants/directory references/document policies; generated external projections, dashboards and finance/communication surfaces; then explicit operational contracts, bounded authorized reads, cohesive authoring/command boundaries and full recreation/preservation acceptance. Each sprint has unchecked tasks, independent acceptance criteria, dependencies and progress tracking. The structural pass's 190-test result remains historical baseline evidence, not proof that these remaining tasks are complete.

The unstarted pilot Sprints 09/10/11/12 become 12/13/14/15, preserving their tasks, task suffixes, acceptance requirements and dated local restaurant notes. The [shared roadmap](../sprint_plan/first_customer_roadmap.md#scope-tracking) records the old/new mapping and finding ownership. Completed Sprints 00–08 and historical evidence are unchanged. The next implementation increment is Sprint 09; no implementation, deployment or launch is performed by this planning update. Durable drafts, physical POS-80 acceptance, access recovery and real-customer operating/data gates remain required in their renumbered pilot sprints.

### D-28 — Establish builder contracts before capability expansion (2026-10-21)

Following the user's request to review and correct Sprints 09–11 against the maintainable modular builder/processor goal, the plans now adopt the [builder architecture contract](../docs/builder-architecture-contract.md). S09-T05 starts the shared ownership, dependency, execution and binding boundary before new participant work. Sprint 10 uses that boundary, introduces bounded projection interfaces and replaces inferred finance correction resets with explicit declarations. Sprint 11 completes compatibility, performance and preservation acceptance rather than being the first integration point.

Recreation fixtures start in Sprint 09 and grow to cover all four original school projects, restaurant service and a synthetic equipment service desk built from a blank definition. Composed-effect rollback, current revocation, pinned business semantics, path-specific publication errors and forbidden-dependency checks are required. Existing contexts should be reused; no dynamic plugin framework, arbitrary rules or new parallel/orchestration scope is introduced. This decision originally revised planned work only; historical validation evidence is unchanged.

### Sprint 09 contract implementation — 2026-10-21

Under the user's authorization to execute the plan, S09-T05 now establishes pure
catalog validation, separate scoped mapping resolution, closed capability
descriptors, the shared existing transaction protocol and incremental recreation
fixtures. The initial participant slice adds declared manager/relationship
policies, audited revision-safe verification/revocation and RLS ownership.
Legacy authorization is isolated behind an explicit adapter; new participant
definitions cannot select guardian compatibility behavior.
See [execution contracts, allowlist and evidence matrix](../docs/builder-execution.md).
At that initial increment S09-T01 backfill/recovery and S09-T02–04 remained pending.

### Sprint 09 completion — 2026-10-21

The continued implementation completes S09-T01–04: external identities separate
from school invitations/staff authority; generic relationship-management controls;
scoped participant/authenticated-subject references; field-declared private-file
permissions and review; audited guardian backfill/synchronization; populated
two-organization backup/restore; and common-route recreation/race acceptance.
The [operator contract and evidence matrix](../docs/participants-and-documents.md)
record supported targets, legacy allowlist and limits. All 224 tests, precommit,
asset build and whitespace checks pass. Sprint 09 is Done, 5/5.
Richer projections, scale/full replacement and pilot gates remain Sprints 10–15.

### D-29 — Sprint 10 execution gates after Sprint 09 review (2026-10-22)

Before Sprint 10 execution, the user requested a final planning revision. Preserve
its four tasks and feature scope, but make the first participant experience an
evidenced vertical slice before broader expansion. Carry corrected Sprint 09
eligibility, subject-without-access and explicit staff-grant behavior into all new
surfaces. This checkpoint is an implementation review, not a new approval gate.

Sprint 10 implements bounded authorized queries for every surface it introduces
or migrates; Sprint 11 reuses that service for remaining old paths and full scale
measurement. Curated communications have explicit release authority independent
of internal-record access, pinned content semantics and current recipient checks
at dispatch/retry. Finance resets and summaries require declared targets, atomic
effects and distinct account authority. Generated navigation and pinned-record
routes must work for participants who cannot create records. The sprint's
scenario mapping makes each original school behavior reviewable without example
dispatch or hidden setup. No implementation completion or pilot activation is
inferred from these clarifications.

### D-30 — Sprint 11 acceptance after corrected Sprints 09–10 (2026-10-22)

Retain Sprint 11's five tasks and feature boundary. Reuse the completed bounded
projection service and shared participant authorization/form conversion rather
than implementing a second version. Inventory residual legacy callers explicitly.
Prove a small restaurant composition through common authoring and generated routes
early, including late settlement rollback, before claiming full recreation.

The two Sprint 10 review defects show that context correctness alone does not
prove consistent public entry points or generated forms. Add a supported-field/
surface matrix and direct-URL/event authorization parity, preserving pinning,
current revocation, explicit staff grants and curated release semantics. Do not
expand deferred field/surface combinations as an incidental acceptance change.

Scale evidence must vary published versions and processes as well as records,
measuring policy compilation and supporting-query cost beyond query count. Record
numeric read/memory budgets before tuning alongside the existing D-09 targets;
retain failures and justify target changes. These refinements establish evidence
checkpoints, not new approval gates or customer-launch authorization.

### D-31 — Begin Sprint 11 with explicit operational semantics (2026-10-22)

The first T01/T03 increment declares `interface.operations` v1: captured actor
name, full manual BRL settlement, a nonempty subset of cash/card/Pix, organization
timezone and estimated product units. Missing declarations retain historical
semantics. New APIs/forms use `responsible_actor`; old waiter payloads and storage
remain adapters without rewriting records or receipt digests. Session commands
and replay resolve the ticket's pinned contract and revalidate current grants.
Editor/import/schema/runtime checks and late settlement rollback cover the early
independent restaurant and composed finance checkpoint.

Read budgets/distributions are fixed in verification before T02 tuning. The
[checkpoint inventory](../docs/sprint11-operational-checkpoint.md) explicitly leaves
supporting-volume measurements, residual read paths, complete public-entry/form
matrices, removed-page fallback, full recreation and populated restoration open.
Sprint 11 is In progress, 0/5; this decision does not close an architecture or
customer activation gate.

### D-32 — Evidence-based retirement of legacy execution (2026-10-22)

The user identified the maintenance cost of compatibility for a system being
sunset after Sprint 11 had started. Preserve the first operational checkpoint;
audit its compatibility mappings rather than restarting the sprint. Blanket
preservation of all historical execution is superseded by a T03/T04 disposition
register and a T05 retirement gate in Sprint 11.

Every adapter needs actual consumer/record evidence, required behavior, an owner,
and a removal milestone or measurable condition. Synthetic-only dependencies are
recreated with supported contracts and their runtime paths removed. Retained
history preferably uses export/snapshots/read-only access. Active consumers may
justify a small migration/drain adapter. Unknown consumers are investigated before
acceptance; local fixture usage alone proves neither production need nor safe data
deletion. New definitions must not acquire dependencies on retired behavior.

Supported builder version pinning, live authorization, audit, idempotency and
populated recovery remain required. Preservation of data is distinct from keeping
obsolete write APIs available; pending jobs need an explicit disposition. Keep
business/security coverage when replacing legacy tests. This is a compatibility
scope revision, not authorization to delete user data or reset environments.

### D-33 — Fresh bounded composite reads and measured readiness (2026-10-23)

Keep the existing projection owner and current tenant/grant/relationship checks.
Group immutable policy bodies only within a query when their policy inputs and
local bindings match; retain actual pin IDs, labels and field schemas where used.
Version-first authorized EXISTS discovery bounds repeated page/message work.
A connection lease may cover a composite authenticated web read, but supplies no
authority and does not replace context transactions. No cross-request policy cache
is introduced.

Generated lists load their record data on the connected pass and preview 80
characters; full detail remains available. Visible completion waits for connected
records and paint. Preserve the predeclared Sprint 11 workload and budgets, retain
failed phases, and distinguish decoded payload, TCP protocol totals, browser
frames, caller heap and full-VM samples. ANALYZE after bulk import/restore is an
explicit readiness prerequisite, not a reduced workload. Workstation acceptance
does not replace S14 real-host capacity verification. See the
[consolidated evidence](../docs/sprint11-final-acceptance.md).
