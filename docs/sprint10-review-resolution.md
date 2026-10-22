# Sprint 10 review corrections

Implemented 2026-10-22 against the two reproduced P2 findings in the
[Sprint 10 architecture review](sprint10-architecture-review.md).
The [correction evidence](evidence/sprint10-review-resolution.json) supplements
the original completion record; the earlier source hashes remain historical.

## Direct document release boundary

`PrivateDocuments.download/2` now uses a download-specific policy combining the
existing tenant, ticket, section, ready-file and declared-file checks with the
participant release boundary. For an identity restricted to participant surfaces,
an applicable **pinned** participant page must select that exact section/field and
currently admit the identity. Knowing the object URL does not release an unselected
file. Current page visibility, audience and underlying relationship/section authority
are checked by the existing shared participant policy.

Declared staff workspace authority keeps staff downloads under the existing section
and file policy, including parent identities with explicit scoped staff grants.
Pinned definitions without participant pages retain their existing document policy,
including historical guardian access. A new publication removing a page does not
rewrite access for an old record: its pinned page still governs the download.

This check lives at the document authorization entry point used by the controller,
so context and direct HTTP downloads agree. It does not turn a page selection into
an underlying grant or change document review/upload authority.

## Shared form transport conversion

`InstantflowWeb.FieldValues.cast/2` now supplies the conversion used by both common
record forms and participant field forms. It removes only empty multiple-select
transport values. Selecting A with the browser-shaped `["", "A"]` stores `["A"]`;
clearing all options with `[""]` stores `[]`. Nonempty forged options remain present
for rejection by the runtime's unchanged declared-option validation. Existing
integer/money/reference, boolean and empty-value conversions are shared as well.

## Maintained regression coverage

`Sprint10ReviewRegressionsTest` promotes both review probes into the normal suite
and extends them to cover:

- Empty document projections deny both context and direct HTTP downloads while
  staff and explicitly granted parent staff retain legitimate access.
- Selecting one of two document fields releases only that exact field.
- A later publication removing the page preserves old-record pinning.
- Relationship revocation denies a previously selected direct URL.
- Removing page visibility authority denies the URL while the identity still has
  underlying section read access, proving the narrower admission check matters.
- Participant and ordinary record forms both select and clear multiple-choice
  fields using actual hidden-input payloads, and reject forged nonempty options.

Focused validation also runs existing declared-document and historical enrollment
document tests. The full required `mix precommit`, asset build and whitespace checks
are recorded in the linked evidence.

Verification passed: 15 focused tests (seed 199162), followed by `mix precommit`
with 273 tests, zero failures (seed 489669), asset build and whitespace checks.

These are targeted corrections within the existing configurable builder design.
No domain-specific screen, parallel authorization engine, relaxed runtime validation
or new dependency was introduced. Sprint 11 retains broader supporting-query volume,
cross-domain recreation and populated compatibility acceptance; neither correction
claims to complete that work or authorize deployment.
