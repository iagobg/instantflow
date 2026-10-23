# Sprint 11 first checkpoint review

Reviewed 2026-10-22 against the working tree based on commit
71ecf2ef9efc882e468aafbcf2164c53fb4c974a. Scope includes the first operational
checkpoint and its subsequent D-32 retirement changes.

## Assessment

The checkpoint advances the modular builder: operational semantics are explicit
and validated, session operations use pinned contracts/current grants, common
editor controls configure payment choices, and independent restaurant fixtures
exercise captured prices, destination batches and late settlement rollback with
finance composition. Retirement removes school-specific policy and route
coupling while preserving historical data separately from executable behavior.

Two reproduced P2 gaps prevent accepting retirement as complete. They require
targeted lifecycle corrections, not restoration of legacy execution.

## P2: Archived open sessions block replacement operations

Locations: lib/instantflow/operations.ex lines 221–224 and 409–414, together with
the retirement migration's operational disposition.

Retirement preserves open sessions but correctly prevents settling them. Resource
occupancy and day closure still count these sessions as live work. After a
supported replacement publication in the same process, opening the resource fails
with :occupied and closing the business day fails with :open_sessions. Settling
the old session fails with :retired_version, leaving no supported way out.

The independent probes open a session, classify its version through the operator
repository, publish a supported replacement through clone/save/publish, and try
resource reuse and day closure. Both fail as described. This models the migration's
resulting state; it is not itself a full migration rehearsal.

Correction: define an explicit archival disposition for open sessions and pending
batches without falsely marking them paid or erasing financial history. Apply it
to occupancy, database uniqueness constraints, workspace availability, day-close
checks and reports. Add populated operational migration/restore coverage followed
by replacement publication and resource reuse in the same process. A UI-only fix
or silent removal of historical money from reports is insufficient.

The checkpoint report acknowledges that operational tables in the recovery fixture
are empty. This limitation should become a concrete regression test now.

## P2: Opening receipt replay validates the latest version instead of its result

Locations: lib/instantflow/operations.ex lines 14–17, 32–37 and 534–535.

For open_session, command version resolution uses the latest publication before
receipt lookup. After a supported replacement is published, its retirement check
passes and the original opening receipt returns without checking the pinned
version of the session referenced by its result.

Replaying the exact original opening command/key after retirement returns success
with the old session ID instead of :retired_version. This contradicts the claimed
denial of archived successful receipt replay. The probe demonstrates a replay
version/authorization gap, not duplicated writes or successful archived settlement.

Correction: resolve and authorize the receipt's result session against its pinned
version and retirement status before returning it. Keep digest mismatch and current
revocation checks; genuinely new openings still use the current publication. Test
replay across retirement, supported publication changes and revoked access, with
no duplicate session or receipt.

## Independent verification

- mix precommit: 287 tests, zero failures, seed 887855.
- Three isolated probes: three failed assertions, seed 438489, reproducing resource
  occupancy, day closure and opening receipt replay.
- Probe file: .local/sprint11_checkpoint_review_probe_test.exs. An initial attempt
  failed in fixture setup; the reported reproductions use the corrected supported
  clone/save/publish path.
- git diff --check passed before writing this report.

No production code was changed. Deployment, browser timing, assets and backup
restoration were not independently rerun. The documented intermittent copied-trip
LiveView reload remains unresolved; a passing rerun does not establish a fix.
Wider scale, full field/surface and public-entry matrices, mixed-version navigation
and populated operational preservation remain Sprint 11 work.

Accept the architectural direction and demonstrated operational slice, but address
these two integration gaps before closing the retirement checkpoint.

## Execution follow-up — 2026-10-23

Both P2 findings were implemented as targeted lifecycle corrections. See the
[resolution and populated operational recovery evidence](sprint11-first-checkpoint-review-resolution.md).
Open retired sessions and pending batches now have an audited unpaid archive
state, preserving historical money while freeing resources and day closure.
Opening replay checks the result session's pinned permission/retirement state.
The original assessment and reproductions above remain the pre-correction record;
Sprint 11's wider gates and the intermittent LiveView observation remain open.
