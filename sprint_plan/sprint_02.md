# Sprint 02 — Permissions and live collaboration

[Sprint index](sprint_index.md) · Status: Planned · Dependencies: Sprint 01A; D-13

Goal: safe collaboration through authorized live tables and section forms.

## Tasks

- [ ] S02-T01 Implement organization-local role/department/relationship/stage policies and restricted projections on the migrated tenant boundary.
- [ ] S02-T02 Build tables, filters, scoped counts, subscriptions, reconnect/reconciliation.
- [ ] S02-T03 Add section editors, advisory presence, pending states, conflict reconciliation.
- [ ] S02-T04 Implement revocation invalidation and transactional authorization coordination.
- [ ] S02-T05 Verify real overlapping database transactions and multi-session scenarios.

## Acceptance criteria

- Same-section writes cannot silently overwrite; losing authorized draft is preserved.
- Independent sections save without unnecessary conflicts.
- Competing transitions commit once; changed reviewed content requires renewed review.
- Revoked users cannot refresh protected data or mutate records; protected UI clears.
- Duplicate/out-of-order events and disconnects converge.
- Counts, history, presence, and events do not reveal hidden records.
- A shared user's different organization roles never combine; concurrent tabs, membership revocation, and live events remain scoped. Retain Sprint 01A isolation regression coverage while adding finer policies.

## Progress

Actual start / finish: — / —  
Evidence: none yet.  
Blockers: resolve D-13 before Ready; decision owner: product owner.  
Handoff: reusable access and live UX.
