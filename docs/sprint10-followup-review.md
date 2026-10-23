# Sprint 10 follow-up architecture review

Reviewed on 2026-10-22 at commit
`71ecf2ef9efc882e468aafbcf2164c53fb4c974a`.

## Outcome

Both findings in the [initial review](sprint10-architecture-review.md) are resolved.
No new actionable findings were identified in the follow-up changes. Sprint 10 is
acceptable within its defined scope and remains aligned with the modular process
builder design. This assessment combines the earlier sprint-wide review with
inspection and independent verification of the subsequent correction commit.

## Document release boundary

`PrivateDocuments.download/2` now combines the existing section/file checks with
`ParticipantPolicy.document_released?/5`. Participant-only access requires an exact
document field selected by a currently admitted page from the record's pinned
definition. It reuses the existing visibility, audience and record-discovery policy
rather than implementing a separate authorization engine in the controller.

The transaction refreshes identity/grants, and the document path resolves the
locked ticket's pinned version. Page selection cannot grant underlying section
read authority. Staff workspace access remains governed by the existing common
predicate, and definitions without participant pages retain their previous policy.

Maintained tests cover context and direct HTTP denial, exact field selection,
publication pinning, relationship revocation, loss of page visibility while
section access remains, and legitimate staff access including explicit parent
staff grants. Existing document tests retain declared and historical coverage.

## Shared form conversion

Both participant and ordinary record forms now use `InstantflowWeb.FieldValues`.
It strips empty multiple-select transport sentinels while leaving nonempty values
for runtime validation. This removes the duplicated conversion path responsible
for the original inconsistency without weakening declared-option validation.

Maintained LiveView tests cover selection, clearing all selections and rejection
of forged options on both surfaces. The shared helper preserves the previous
ordinary form conversions for numbers, references, booleans and empty values.

## Independent verification

- Required `mix precommit` stages completed; 273 tests, zero failures, seed 862681.
  The shell wrapper subsequently failed when forwarding its exit-status variable;
  that wrapper error occurred after the successful test summary, not in a Mix stage.
- Original independent review probes: two tests, zero failures, seed 491635.
- `git diff --check` passed before adding this report.

No production code was changed during this follow-up review. No deployment or
external delivery was exercised. Sprint 11 still owns restaurant operational
generalization, broader supporting-query volume checks and full cross-domain
recreation/preservation acceptance. Accepting Sprint 10 does not establish those
later outcomes or customer-launch readiness.
