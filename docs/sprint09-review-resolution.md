# Sprint 09 review corrections

Implemented 2026-10-22 in response to the
[architecture acceptance review](sprint09-architecture-review.md). The original
review and pre-review evidence remain historical records; the refreshed
[local evidence](evidence/sprint09-local.json) identifies the corrected tree.

## R09-01 — Subject eligibility independent of authority

Relationship declarations now contain `candidate_roles`, referencing portable
symbolic role requirements and their local bindings. Typed authoring exposes a
separate eligible-role selector. Publication rejects missing/empty candidate roles
and unknown role keys with a path-specific diagnostic. Selecting a subject does
not require adding subject actor permissions.

The picker and create/verify commands share one eligibility query: current active
local membership and user, an explicitly mapped candidate role (base or grant),
and a different user from the acting manager. Queries retain scoped substring
search, 100-character input and 25-result limits. Foreign memberships remain
indistinguishable from missing records. Existing links remain manageable; a lost
candidate grant blocks verify and create/verify retries, while revoke remains
available. Role eligibility never grants record access.

Previously pinned participant versions without `candidate_roles` retain their
original inferred picker eligibility, now applied to commands too. Historical
JSON is not rewritten. New publication requires explicit eligibility; clone and
configure the roles to adopt the corrected subject-only contract.

Maintained coverage:

- `participant_directory_live_test.exs` configures a subject-only definition,
  invites an external subject, searches/adds/verifies via LiveView, stores a
  non-null subject reference and proves the subject cannot read/search the record.
- `sprint09_review_acceptance_test.exs` checks portable publication diagnostics,
  grant-derived eligibility, revoked retries, inactive users/memberships,
  cross-organization membership IDs for a shared identity, and pinned eligibility
  across a later publication.
- `templates_live_test.exs` exercises the typed candidate-role selector.

## R09-02 — Declared roles for parent and external memberships

Actor evaluation now delegates the historical base-parent restriction to
`LegacyAccess.parent_portal?/2`. Definitions declaring participants evaluate their
current role mappings and scopes for every base membership, including internal
department manager and document reviewer rules. A participant relationship alone
does not satisfy those rules. Ticket discovery uses the same compatibility
boundary; creation, creation discovery and creation receipt retry share the
current creation policy.

Maintained acceptance coverage exercises parent and external memberships with a
teacher grant, wrong-department denial, manager controls, section discovery,
independent document review, creation and replay. Removing grants denies subsequent
staff actions and creation/retries. Plain unrelated parents/external memberships
remain denied. A populated legacy enrollment is kept pinned while a declared
version is published on the same workflow: its old parent portal projection,
generic-route restrictions and immutable definition remain intact.

No migration, historical-data rewrite or remote deployment is required for these
corrections. Full school replacement and later Sprint 10–15 gates remain unchanged.

## Verification

- `mix precommit`: 231 tests, 0 failures, seed 838455, including the school/privacy,
  populated migration/restore and independent runtime revocation regressions.
- The reviewer's unchanged `.local/sprint09_review_probe_test.exs`: 2 tests,
  0 failures. Corrected cases are also in normal maintained test discovery.
- `mix assets.build` and `git diff --check`: passed.

The refreshed evidence records log hashes and source hashes for the combined
uncommitted working tree. The original 224-test completion evidence is retained at
`docs/evidence/sprint09-pre-review.json`; it is superseded for current acceptance.
