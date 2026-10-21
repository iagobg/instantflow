# Decision register

[Design index](index.md)

| ID | Status | Question / decision | Direction | Needed by |
|---|---|---|---|---|
| D-01 | Confirmed — supersedes earlier scope | Organization scope | Multiple isolated organizations from this development round; migrate existing foundation | Sprint 01A |
| D-02 | Confirmed | Customization | Administrator constrained visual editor | Editor |
| D-03 | Confirmed | Integrations | Explicit demo payments/notifications/provisioning | First slice |
| D-04 | Confirmed | Language and stack | PT-BR; Elixir/Phoenix LiveView; non-authoritative JS | Foundation |
| D-05 | Open | Guardian verification | Proposed: staff invitation and manual verification; multiple guardians | Sprint 04 |
| D-06 | Open | Incident/support visibility | Proposed: assigned counselor-private notes; curated parent communication | Sprint 06 |
| D-07 | Open | Budget/cancellation/price changes | Proposed: reserve at finance approval; commit at order; explicit reversals | Sprint 05 |
| D-08 | Adopted for implementation | Parallel branches now? | Sequential stages, independent sections | Sprint 01 |
| D-09 | Open | Hosting/load/timezone | Proposed: shared deployment; 10 organizations, 50 concurrent staff/10,000 tickets total; per-organization timezone default America/Sao_Paulo | Sprint 07 |
| D-10 | Open | Parent self-registration? | Proposed: invitations only; no anonymous uploads | Sprint 04 |
| D-11 | Open | Parent-visible status/messages | Proposed: explicit public projection | Sprint 04 |
| D-12 | Open | File types/sizes/retention | Proposed: bounded private PDFs/images; synthetic data pending retention rules | Sprint 04 |
| D-13 | Adopted for implementation | Self-approval | Prohibit finance-sensitive self-approval, including overlapping local roles; no override in this increment | Sprint 02 |
| D-14 | Adopted for implementation | Definition changes | Immutable versions; existing tickets pinned | Sprint 01 |
| D-15 | Proposed following user suggestion | Interchange and LLM guide | Versioned JSON, draft-only imports, local mappings, shared validation; external LLM authorship | Sprint 03 |
| D-16 | Recommended planning direction | Customer-authored Python | Gated extension after Sprint 07; asynchronous isolated calculations, declared inputs/outputs, no direct side effects; see design 10 | Sprint 08 gate |
| D-17 | Open | First real scripting need and hosting boundary | Select one calculation that bounded guards cannot express; establish runner isolation, operating cost, and security ownership | Before Sprint 08 implementation |
| D-18 | Adopted for implementation | Tenant persistence/isolation | Shared schema, mandatory tenant scopes, composite ownership FKs, runtime-role RLS; no cross-organization records | Sprint 01A |
| D-19 | Adopted for implementation | Users and organization selection | Global login identity; independent local memberships; organization in route/tab context; no cross-tenant role inheritance | Sprint 01A |
| D-20 | Adopted for implementation | Organization lifecycle and administration | Operator-managed provisioning/suspension; organization-local administrators; no default support data access, billing, signup, or deletion | Sprint 01A |

## Recorded answers — 2026-10-20

The user initially chose one organization, a visual editor, and explicit simulations. The later explicit request for a multi-organizational platform supersedes the first choice only. The visual editor and simulations remain confirmed. The design recommends import/export and an LLM guide, with D-15 kept Proposed.

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
