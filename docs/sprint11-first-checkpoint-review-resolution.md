# Sprint 11 first checkpoint review — corrections

Executed 2026-10-23 against the existing uncommitted Sprint 11 working tree,
base revision 71ecf2ef9efc882e468aafbcf2164c53fb4c974a. Scope: the two P2 findings
in [the checkpoint review](sprint11-first-checkpoint-review.md). This does not
close Sprint 11's wider acceptance gates.

## Archived operational work no longer blocks replacement work

The forward migration `20261023033124_archive_retired_operational_work.exs`
changes only open sessions of retired versions to `archived` and their pending
batches to `archived`. It records `retired_session_archived` and
`retired_batch_archived` organization audit entries. This disposition means
neither paid nor handed off. Already settled sessions retain their exact totals,
payment methods and settlement instants; handed and cancelled batches retain
their status. Captured lines, names, prices, quantities, notes, receipts,
cancellation source IDs, immutable definitions and prior day snapshots remain.

The oldest versions may predate capability declarations. Actual session/ticket
lineage without a declared operational contract is also classified in the
operator-owned retirement table. An ordinary core-only definition without a
session is not classified. Newly classified queued deliveries/calculations receive
the same audited cancellation as the original D-32 migration; their payloads stay
intact. All FORCE RLS settings are restored within the migration transaction.

The session constraint permits unpaid `archived` rows with no settlement instant
or payment method. The existing partial unique index continues to enforce one
`open` session per resource. Archived rows are outside that predicate, workspace
occupancy and day-close checks. No duplicate/live occupancy exception is introduced.
This removes the blocker at the stored-state boundary used by every caller.

Reports expose `archived_count` and `archived_total` separately from open balances,
sales and receipts, including in newly saved day-close summaries. The archived
amount uses captured non-cancelled order lines, rather than current catalog prices
or a false settlement amount. Paid history remains in sales/payment totals;
cancelled orders remain in cancellation totals. Estimated requested product units
continue to include retained archived orders, explicitly labelled as neither
proof of delivery nor stock usage. Previous immutable summaries are not rewritten.
Generated pages show archived unpaid amounts and batch status, retain history,
and offer the released resource for a supported replacement session.

## Opening receipt replay follows its pinned result

Receipt lookup remains tenant-, process- and actor-scoped under the authorization
and operations gates. An existing opening receipt resolves its result session and
that ticket's pinned version before checking operational permission and retirement.
The latest publication is used for genuinely new openings. A supported opening
can replay after publication changes using its original policy and current grants;
a retired result returns `retired_version` even if the latest version is supported.
Current revocation is checked before returning any receipt or retirement detail.
Payload changes still return `idempotency_mismatch` for an admitted actor. Failed
and successful replay add neither sessions nor receipts.

## Regression and recovery evidence

- `operations_retirement_replay_test.exs`: exact opening replay after retirement
  and replacement publication; supported replay across changed role bindings;
  latest-policy denial for new openings; digest mismatch; current grant revocation;
  unchanged session and receipt counts.
- `operational_retirement_migration_test.exs`: creates an actual pre-retirement
  database with two organizations, four populated sessions, ten order/cancellation
  batches, captured lines, opening receipts and prior day snapshots. Forward
  migration archives only the retired tenant's unpaid session and two pending
  batches. Whole-database pg_dump/pg_restore compares retained row snapshots,
  retirement classification and audit. The restored runtime connection enforces
  RLS and cross-tenant denial. Supported clone/save/publish then installs a new
  version in the same process, reuses the same resource, settles its new session
  and closes the day while retaining 1,500 cents of unpaid archived history and
  2,500 cents of actual paid sales.
- `process_migration_test.exs`: retains the earlier pre-process-schema fixture and
  verifies its actual session lineage becomes read-only archived history, preserving
  captured 1,200 cents and all other original fields/provenance.
- `archived_record_live_test.exs`: generated resource options expose the released
  resource; archive amount is separate from sales; actual rendered opening form
  creates a replacement visit; direct archived pages display captured batch history
  with no handoff or checkout controls.
- Existing operations tests retain handoff/checkout guards, live occupancy, resource
  reuse, settlement replay, totals, cancellation and closed-day checks.

The [machine-readable evidence](evidence/sprint11-first-checkpoint-review-resolution.json)
records test counts, seeds and exact source/log hashes. The prior checkpoint's
empty-operational-table recovery report stays historical; the new populated
regression addresses that specific gap without rewriting earlier evidence.

## Operator and sprint status

Apply forward migrations in a maintenance window after a verified private backup.
Use the new archive audit entries to reconcile retained unpaid work; do not label
it as received money or resume its batches. Do not restore runtime writes to legacy
source tables. Rollback is forward-only; use coordinated backup recovery.
No serving database was migrated or written, and nothing was deployed by this work.

Both reproduced P2 findings are addressed. The intermittent copied-trip LiveView
reload remains unproven as a fix; these changes do not relax its tests or add retry.
Sprint 11 remains In progress, 1/5. T02 scale, complete T03 field/surface/public-entry
matrices, T04 residual ownership work and T05 full recreation remain open. Physical
printing and real-host/customer acceptance remain later gates.
