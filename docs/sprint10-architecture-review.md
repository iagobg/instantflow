# Sprint 10 architecture review

Reviewed on 2026-10-22 against commit
`aff310a506392f47b5f9abd8bb6df3cc853fb960`.

## Assessment

Sprint 10 substantially advances the intended configurable, modular process builder.
The implementation composes published declarations with shared runtime services,
rather than adding separate application runtimes for each example. It is aligned
with the architecture contract, but two reproduced gaps should be corrected before
accepting the participant experience as complete. These call for targeted fixes,
not another redesign.

The strongest evidence of alignment is:

- Participant pages use declared audiences, selected fields/documents/actions,
  pinned definitions and current relationship/section authority. Shared services
  handle commands; page configuration does not itself grant mutation permission.
- Bounded projections apply authorization before counts and pagination. Configured
  views build on that common query boundary instead of independently filtering
  records inside each screen.
- Finance surfaces distinguish process-scoped totals from shared-account access.
  Explicit correction/reset declarations replace inferred behavior for new
  definitions, with effects inside the runtime transaction.
- Curated communications snapshot selected content and bind recipients explicitly,
  with eligibility checks for release and dispatch. Delivery remains simulated.
- Recreation fixtures exercise school processes with renamed keys and an equipment
  process through common editor/generated surfaces. This is useful evidence of
  composition beyond the original domain, though it is not proof that every future
  restaurant process is already expressible.

## Findings

### P2 — Direct document download bypasses the participant document projection

Location: `lib/instantflow/private_document_policy.ex:11-14`; also the direct
download path through `DocumentController` and `PrivateDocuments.download`.

The declared-document policy checks section authorization but does not check the
narrower participant projection. A participant-only identity can download a ready
file through its known direct URL even when the pinned participant page selects
no documents. The page correctly omits the file, and its upload wrapper rejects
the same unselected document field, so the two entry points disagree.

Reproduction: install a participant page with `documents: []`, link and verify an
external participant, create and review a document in an otherwise authorized
section, then request its document URL as that participant. The page returns no
documents, but the HTTP response is 200 rather than the expected denial.

This is a bypass of the page's narrower release selection, not a demonstrated
bypass of tenant or underlying section authorization. It requires knowledge of
the object URL; the probe does not establish enumeration of object keys.

Correction: enforce the participant document release boundary at the download
authorization entry point for identities restricted to participant surfaces.
Require admission to an applicable pinned page selecting the document, in
addition to existing record, section and document checks. Preserve legitimate
staff and historical access explicitly. Add direct-URL regressions for selected
and unselected fields and for loss of page admission or current authority.

### P2 — Multiple-choice participant fields reject normal browser submissions

Location: `lib/instantflow_web/live/participant_live.ex:284-295` and the multiple
select rendered at line 365.

The shared input component emits an empty hidden value for a multiple select, so
selecting A submits `["", "A"]`. ParticipantLive passes that list through unchanged.
The runtime correctly rejects the empty string as an undeclared option, leaving
the field unsaved. The generic record form already removes this sentinel in
`RequestLive.cast_values/2`, but the participant form has a separate conversion
path that omits it.

Reproduction: publish a participant field with type `multiple_choice` and options
A/B, confirm the hidden input is present, and submit the browser-shaped payload.
The stored value remains nil rather than becoming `["A"]`.

Correction: normalize multiple-choice input consistently across generated forms,
preferably through a small shared conversion function. Test selection and clearing
all selections, while retaining rejection of forged nonempty options. Do not relax
the runtime's declared-option validation to accommodate transport sentinels.

## Independent verification and limits

- `mix precommit`: 268 tests, zero failures, seed 642452.
- Two isolated regression probes: two failures, seed 108618, reproducing the
  findings above. They are in `.local/sprint10_review_probe_test.exs`, outside the
  regular test suite; promote the relevant cases into maintained tests with fixes.
- The review inspected the implementation and exercised LiveView/controller tests;
  it did not perform a deployed browser acceptance run or external message delivery.
- Catalog-version loading and broader volume validation remain follow-up concerns
  already documented for Sprint 11. A bounded record page alone does not establish
  bounded cost for every supporting query.

No production implementation was changed by this review. Keep the current design
direction, address these two acceptance gaps, and retain Sprint 11's cross-domain
recreation and scale checks. The main prevention lesson is to test every public
entry point against the same declared projection and every supported input type
against the actual form payload, not merely test the shared runtime in isolation.
