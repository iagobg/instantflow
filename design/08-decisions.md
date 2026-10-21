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
| D-09 | Open | Hosting/load/timezone | Proposed: shared deployment; 10 organizations, 50 concurrent staff/10,000 tickets total; per-organization timezone default America/Sao_Paulo | Sprint 07 |
| D-10 | Adopted for synthetic demonstration — 2026-10-21 | Parent self-registration? | Invitations only; no anonymous uploads | Sprint 04 |
| D-11 | Adopted for synthetic demonstration — 2026-10-21 | Parent-visible status/messages | Explicit allowlisted public projection; no internal runtime/history access | Sprint 04 |
| D-12 | Adopted for synthetic demonstration — 2026-10-21 | File types/sizes/retention | Private PDF/PNG/JPEG ≤ 5 MiB, 20 active files/ticket; quarantine/manual release, 30-day synthetic retention | Sprint 04 |
| D-13 | Adopted for implementation | Self-approval | Prohibit finance-sensitive self-approval, including overlapping local roles; no override in this increment | Sprint 02 |
| D-14 | Adopted for implementation | Definition changes | Immutable versions; existing tickets pinned | Sprint 01 |
| D-15 | Confirmed — 2026-10-20 | Interchange and LLM guide | Versioned JSON, draft-only imports, local mappings, shared validation; external LLM authorship | Sprint 03 |
| D-16 | Recommended planning direction | Customer-authored Python | Gated extension after Sprint 07; asynchronous isolated calculations, declared inputs/outputs, no direct side effects; see design 10 | Sprint 08 gate |
| D-17 | Open | First real scripting need and hosting boundary | Select one calculation that bounded guards cannot express; establish runner isolation, operating cost, and security ownership | Before Sprint 08 implementation |
| D-18 | Adopted for implementation | Tenant persistence/isolation | Shared schema, mandatory tenant scopes, composite ownership FKs, runtime-role RLS; no cross-organization records | Sprint 01A |
| D-19 | Adopted for implementation | Users and organization selection | Global login identity; independent local memberships; organization in route/tab context; no cross-tenant role inheritance | Sprint 01A |
| D-20 | Adopted for implementation | Organization lifecycle and administration | Operator-managed provisioning/suspension; organization-local administrators; no default support data access, billing, signup, or deletion | Sprint 01A |

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
