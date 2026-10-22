# Sprint 09 architecture acceptance review

Reviewed 2026-10-22 against the intended general-purpose builder, the builder architecture contract and Sprint 09's completion criteria. Assessment: materially aligned, but two reproduced configuration gaps should be corrected before relying on the completed participant/reference foundation in Sprint 10. This review does not replace the original completion evidence or change runtime code.

## Findings

### R09-01 — Subject selection depends on granting process authority (P2)

Location: `lib/instantflow/participants.ex`, `controls/3` and `participant_roles/2` (lines 116–131 and 171–179 at review).

Candidate eligibility is inferred only from participant-scoped section access and transition actors. A valid subject declaration referenced by a directory field, without any subject actor permissions, therefore produces an empty candidate list. Publication accepts it and the manager sees the relationship control, but cannot select anyone through supported UI setup. Creating the relationship through the context API succeeds independently of those inferred roles, so the UI and command contracts also disagree about eligibility.

Reproduction: start with BuilderFixtures.directory_definition; remove customer_details (the only section granting the subject access); change the relationship kind and reference target to subject; map the symbolic roles and publish. Create a ticket and call Participants.controls as the authorized manager. The subject candidate list is empty even with an active local external membership. The existing subject-reference test retains customer_details access and creates links directly through commands, so it does not cover this case.

Impact: an administrator cannot configure an authenticated subject who is merely the subject of a record, rather than an authorized reader/actor. Adding access rules just to populate a picker would couple relationship setup to permissions, contrary to the intended independent contracts. This does not concern anonymous directory people, which Sprint 09 explicitly defers.

Correction: define explicit bounded candidate eligibility for relationships, separate from record permissions, and enforce the same rule in picker queries and create/verify commands. Keep local IDs out of portable definitions and preserve scoped search. Do not solve this with an unrestricted global account dropdown or by automatically granting access. Cover subject-only setup through the LiveView and prove the linked subject still cannot read the record. If this configuration remains unsupported, reject it with an actionable publication diagnostic and narrow the claimed subject support; do not accept an unusable published definition.

Ownership: S09-T02/T04, with declaration/diagnostic consistency under T05.

### R09-02 — Legacy parent gating overrides declared roles in new processes (P2)

Location: `lib/instantflow/workflow_runtime/policy.ex`, `actor?/4` (lines 33–35); also review the unconditional parent creation prohibition in `workflow_runtime.ex` at line 269.

For every non-participant actor scope, actor?/4 requires either a non-parent base membership or LegacyAccess.guardian?. LegacyAccess.guardian? deliberately returns false for definitions with participants. Consequently, a parent membership with an explicitly granted local teacher role cannot satisfy a declared workflow_department manager rule mapped to teacher, although the role and department are correct. It also cannot receive internal section/reviewer authority through that configured rule. The restriction is selected by the historical base role rather than the new process declaration.

Reproduction: grant teacher to a local parent membership through Access.grant; install a participant definition with reviewer mapped to teacher and responsible mapped to that department; create the record as staff. Participants.controls for the explicitly granted manager returns no controls. This is not a request for a broad parent bypass: the user must have the current grant and satisfy the declared scope, and a participant relationship alone must never confer manager authority.

Correction: apply the historical parent/guardian restriction only to the explicit legacy definition path. Declared processes must evaluate current mapped roles and their configured scopes. Audit creation and discovery for the same distinction. Preserve old school portal protections and add regressions for parent-plus-staff grants, plain unrelated parents, external memberships, revocation and pinned legacy versions. Dependency checks that ban Enrollment module calls do not detect literal role-based legacy behavior, so keep outcome coverage as well.

Ownership: S09-T01/T04, with compatibility boundary coverage under T05.

## What the sprint establishes successfully

- Participant relationships have explicit organization, process, ticket and membership ownership, verification state, revisions, receipts and audited changes. They are separate from invitation identity.
- Generic runtime authorization no longer calls Enrollment directly. Legacy guardian lookup reads audited participant mappings, while historical document behavior is isolated behind a named compatibility policy.
- Declared document fields use section/relationship authorization and independent reviewers. Tests exercise upload, readiness, review, revocation and download through generated record routes.
- Pure catalog validation, local bindings and capability metadata have identifiable owners. Dependency checks and late-effect rollback tests supply executable evidence beyond prose.
- The equipment service desk is defined from a blank structure and composes invitation, verification, reference selection, correction, private document release and settlement through supported contexts. LiveView tests separately exercise authoring and participant/document interaction.
- Populated migration/restore and independent runtime-login revocation races are in the passing suite. The migration preserves historical versions and maps guardian state instead of rewriting business history.

This is a substantial correction toward the original design. The two findings identify incomplete configurations within the new contract, not a new domain-specific application disguised as a builder.

## Verification and limits

- Working-tree base: `11b432bc53838515fb63d68e07ce81d28d824be5`; implementation is uncommitted.
- All 110 source hashes in `docs/evidence/sprint09-local.json` matched before this review's artifacts were added.
- Independent `mix precommit`: 224 tests, 0 failures, seed 884150. Migration module redefinition warnings occurred during migration rehearsal; the command exited successfully.
- Additional acceptance probes: 2 tests, 2 failures, seed 338834. These assert the desired behavior for R09-01 and R09-02, rather than weakening expectations to fit the implementation.
- Local reproduction file: `.local/sprint09_review_probe_test.exs`. Run `mix test .local/sprint09_review_probe_test.exs` from the repository with its configured Elixir toolchain. This diagnostic file is outside normal test discovery; promote corrected cases into the maintained tests when implementing fixes.
- No production data, deployment, runtime implementation or existing sprint completion evidence was changed. No new browser session or asset build was performed; UI coverage here is the suite's LiveView tests plus inspection of the shared query used by the picker.

The existing evidence establishes the implemented slice, not full school recreation or production readiness. Authenticated subjects only, richer participant pages, explicit finance resets, complete mixed-version composition, bounded bulk reads and restaurant operational semantics retain their documented later gates.

## Recommendation

Keep the implementation and architecture direction. Reopen the affected Sprint 09 acceptance items for the two reproduced gaps, or track them as explicit prerequisite fixes before expanding dependent Sprint 10 behavior. Accept the foundation after both probes pass through supported setup without widening unrelated access, the original school/privacy tests remain green, and refreshed source evidence records the corrected tree. A general rewrite is not justified by this review.
