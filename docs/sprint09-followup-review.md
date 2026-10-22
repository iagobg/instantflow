# Sprint 09 independent follow-up review

Reviewed 2026-10-22 after the corrections described in [review resolution](sprint09-review-resolution.md). This follow-up supersedes the open-finding recommendation in the [first review](sprint09-architecture-review.md) for the corrected working tree; the original report remains historical evidence.

## Assessment

R09-01 and R09-02 are resolved for the declared participant-process scope reviewed. No new blocking finding was identified in the changed implementation. The participant/reference/document foundation is suitable for proceeding to Sprint 10 under its existing acceptance gates.

R09-01: candidate_roles is a portable symbolic eligibility declaration independent of record permissions. Authoring exposes it; publication rejects absent, empty or unknown roles; scoped picker and create/verify commands share candidate_query. Eligibility checks cover active local identities, current mapped roles/grants and self-verification prevention. Revocation remains possible after loss of candidate grants. The subject-only LiveView test searches, adds, verifies and stores the reference while proving the subject cannot read or discover the record. No access rule is added merely to populate the picker.

R09-02: actor, discovery and creation policy now use the explicit LegacyAccess boundary. A parent or external membership with the required staff grant and scope can manage declared relationships and independently review files. Unrelated participants remain denied; wrong-department and revoked grants fail. Creation discovery and receipt replay use the shared creation policy. Tests preserve old school parent restrictions on pinned records even after a new participant-defined version is published on the same workflow.

The corrections address the contracts, rather than changing the original probes' assertions or introducing example-key exceptions. Maintained tests cover both findings and negative cases.

## Independent verification

- All 114 source hashes in docs/evidence/sprint09-local.json matched the reviewed tree before this report was added. Base revision remains 11b432bc53838515fb63d68e07ce81d28d824be5 with uncommitted implementation changes.
- mix precommit: 231 tests, zero failures, seed 705390; exit status 0. Migration rehearsal emitted module redefinition warnings.
- Original local review probes: 2 tests, zero failures, seed 313619. Probe assertions are unchanged; their shared fixtures now declare candidate_roles as required by the corrected contract.
- git diff --check passed.
- Inspection covered the changed participant queries/commands, policy and creation/replay paths, publication diagnostics, schema, typed authoring, fixture changes and new context/LiveView acceptance tests.

## Limits and handoff

This review did not change runtime code, deploy, run a fresh browser session or rerun the asset build. UI interaction evidence comes from the independently run LiveView tests; the implementation evidence separately records its asset build.

Previously published participant definitions without candidate_roles retain inferred picker eligibility, now enforced by create/verify commands too. This documented tightening is not a rewrite of historical JSON; adopting subject-only eligibility requires explicit configuration and a new publication. The explicit-role correction applies to participant-defined processes; broader legacy replacement remains later work.

This is acceptance of the repaired Sprint 09 foundation, not completion of the general-purpose builder. Sprint 10 must still deliver generated participant projections and other planned surfaces; Sprint 11 must complete full school/restaurant recreation, mixed-capability/version acceptance and bounded read performance. Keep those gates and the incremental recreation matrix in force.
