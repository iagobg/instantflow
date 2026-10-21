# Sprint 05 — Budgets, purchasing, and field trips

[Sprint index](sprint_index.md) · Status: Done · Dependencies: Sprint 04; D-07

Goal: quantitative consistency and cross-department approvals.

## Tasks

- [x] S05-T01 Implement allocations, reservations, postings, reversals, finance permissions.
- [x] S05-T02 Configure requisition approval, purchasing, partial delivery, completion.
- [x] S05-T03 Configure field-trip academic, finance, transport, safety steps.
- [x] S05-T04 Add scoped live budgets, calendar, and bottleneck/assignment views.
- [x] S05-T05 Verify contention, cancellation, revised costs, and cross-template races.

## Acceptance criteria

- Shared-budget concurrent requests cannot reserve more than available.
- Ordering converts reserved funds without double subtraction or duplicate effects.
- Pre-order cancellation releases once; post-order reversal is explicit/audited.
- Partial delivery cannot complete an incomplete order.
- Trips cannot skip academic, finance, transport, or safety prerequisites.
- Approval-sensitive changes require renewed review; viewers converge to committed totals.
- Same-named departments/budgets in two organizations remain independent. Cross-organization account bindings and requests fail, including when the finance user belongs to both schools; calendar/counts expose only the active tenant.

## Progress

Actual start / finish: 2026-10-21 / 2026-10-21  
Evidence: `mix precommit` passed (124 tests, 0 failures); `mix assets.build` passed. Forward migration applied; seeds executed twice successfully without duplicating allocations.  
Blockers: none for the synthetic demonstration. D-07 adopted as an implementation default under the Sprint 05 authorization; real financial operations remain outside scope.  
Handoff: two additional templates and finance capability; Sprint 06 confidential incident collaboration is next.

## Delivery evidence

- T01: [finance context](../lib/instantflow/finance.ex), [ledger migration](../priv/repo/migrations/20261021080918_add_budget_ledger.exs), [accounting tests](../test/instantflow/finance/accounting_test.exs). Account row locks protect shared balances; integer BRL cents, nonnegative available totals, one current hold per request, immutable attributable entries, distinct allocation/reversal grants, self-approval prohibition and safe retry receipts.
- T02: [requisition definition](../priv/workflows/requisition.json). Academic/finance review, reserve-to-spend conversion, required simulated order reference, cumulative partial delivery and exact completion, bounded receiving quantities, pre-order release and full explicit post-order reversal. Revised proposals release funds and repeat both approvals; posted proposals cannot silently change price.
- T03: [field-trip definition](../priv/workflows/field_trip.json). Mandatory academic, finance, transport and safety commands. Changes to dates/destination/participants/cost require return to proposal and all renewed approvals; downstream work is cleared. Approved cancellation requires a full explicit reversal.
- T04: [budget LiveView](../lib/instantflow_web/live/budgets_live.ex), [configured views](../lib/instantflow/workflow_catalog/views.ex), [live tests](../test/instantflow_web/live/budgets_live_test.exs). Authorized live totals/audit, post-commit invalidation with 30-second reconciliation, immediate revocation refresh, date-sorted/paginated calendar agenda, current department assignment, scoped board counts. Two viewers converge after allocation; parent/unrelated staff see no accounts or amounts and cannot forge mutations. Browser smoke checked direct parent access and the rendered restricted layout; staff/calendar interactions are covered by LiveView tests.
- T05: [independent runtime-role tests](../test/instantflow/runtime_role_test.exs). Two distinct finance actors on real non-owner connections block behind the same account row while approving different templates: exactly one commits, one receives insufficient-budget, totals/entry/receipt counts remain correct and winner retry does not repeat effects. Same-named accounts/departments stay independent across schools, even with one finance identity in both; foreign bindings/requests and composite ownership fail, absent/wrong RLS context returns no finance rows, and ledger updates are rejected. [Definition tests](../test/instantflow/finance/definition_test.exs) preserve finance semantics through interchange and typed editing.

Setup, walkthrough, accounting defaults and precise limits: [finance operating notes](../docs/finance.md). The demonstration uses one quantified group per requisition, full reversals only and date-only agenda views. No real orders/payments/credits, emergency guarantee, exhaustive device/accessibility testing or load certification is claimed.
