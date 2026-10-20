# Sprint 05 — Budgets, purchasing, and field trips

[Sprint index](sprint_index.md) · Status: Planned · Dependencies: Sprint 04; D-07

Goal: quantitative consistency and cross-department approvals.

## Tasks

- [ ] S05-T01 Implement allocations, reservations, postings, reversals, finance permissions.
- [ ] S05-T02 Configure requisition approval, purchasing, partial delivery, completion.
- [ ] S05-T03 Configure field-trip academic, finance, transport, safety steps.
- [ ] S05-T04 Add scoped live budgets, calendar, and bottleneck/assignment views.
- [ ] S05-T05 Verify contention, cancellation, revised costs, and cross-template races.

## Acceptance criteria

- Shared-budget concurrent requests cannot reserve more than available.
- Ordering converts reserved funds without double subtraction or duplicate effects.
- Pre-order cancellation releases once; post-order reversal is explicit/audited.
- Partial delivery cannot complete an incomplete order.
- Trips cannot skip academic, finance, transport, or safety prerequisites.
- Approval-sensitive changes require renewed review; viewers converge to committed totals.

## Progress

Actual start / finish: — / —  
Evidence: none yet.  
Blockers: D-07 accounting/cancellation rules; decision owner: product owner.  
Handoff: two additional templates and finance capability.
