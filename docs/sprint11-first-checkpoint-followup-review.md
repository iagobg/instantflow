# Sprint 11 checkpoint 1 follow-up review

Reviewed 2026-10-23 against the uncommitted Sprint 11 working tree based on
71ecf2ef9efc882e468aafbcf2164c53fb4c974a. Scope: corrections to the two findings
in [the first review](sprint11-first-checkpoint-review.md).

## Outcome

Both previous findings are resolved. No new actionable findings were identified
in the correction scope. Checkpoint 1 is acceptable within its operational and
retirement scope; Sprint 11's wider acceptance gates remain open.

## Operational archival

The forward migration gives retired open sessions and pending batches an explicit
archived state. Occupancy queries and the partial unique index still operate on
open sessions, freeing resources for replacement work without weakening live
occupancy protection. Archival means neither payment nor handoff. Captured lines,
settled amounts, receipts and prior summaries remain intact. Reports separate
archived unpaid amounts from sales and live open balances.

The maintained populated migration test runs actual forward migration and
pg_dump/pg_restore across two organizations, checks retained snapshots and RLS,
then publishes a supported replacement in the same process, reuses the resource,
settles new work and closes the day. An unaffected supported tenant still rejects
double occupancy and closing with a live session. LiveView coverage checks resource
options, archive amounts and protected historical controls. This closes the prior
empty-operational-fixture evidence gap.

Old session-bearing versions without capability declarations are classified using
actual session lineage. An ordinary core-only definition is not classified merely
because it omits an optional operational contract.

## Opening receipt replay

Existing opening receipts now resolve their result session's pinned version before
operational authorization and retirement checks. Current grants remain required;
new openings use the latest publication. Digest mismatch stays enforced. Tests
cover retired results, changed role bindings, revoked grants and unchanged session/
receipt counts. The original independent opening-replay probe passes unchanged.

## Independent verification and limits

- mix precommit: 291 tests, zero failures, seed 33681, including populated
  operational migration/restore and maintained replay regressions.
- Original opening-replay probe at .local/sprint11_checkpoint_review_probe_test.exs:44:
  one test passed, seed 428839; two other probes excluded.
- git diff --check passed before this report was written.

The original occupancy probes insert a retirement classification after all
migrations have run, without applying the new archival disposition. The actual
populated migration/restore test now verifies those outcomes; this review does
not claim the unchanged occupancy probes passed.

No production code changed. Assets, deployment and browser timing were not
independently rerun. The previously documented intermittent copied-trip LiveView
reload has no established fix: this passing full run does not establish its cause.
T02 scale, complete T03 field/surface/public-entry matrices, T04 residual ownership
work and T05 full recreation remain open.
