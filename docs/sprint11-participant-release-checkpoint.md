# Sprint 11 participant release parity checkpoint

Executed 2026-10-23 on field/surface revision a37ca1a. Scope: the T03
multiple-participant-page release and entry-point parity gate. This checkpoint
adds acceptance evidence for the existing policy; no authorization implementation
change was required. Full T03 remains open.

## Scenario and asserted boundary

The independent process has a descriptive first participant page with no files,
a second page selecting one exact document, a page requiring an additional live
role, and a page selecting a confidential section that the participant cannot read.
Other documents in the readable section are deliberately omitted. All document
fields have explicit pinned policies. Setup imports/maps/publishes the definition,
creates the record and verifies relationships through supported contexts. Uploads
and reviews use different authorized identities. Only the low-level second-tenant
organization/membership fixture uses direct setup inserts; no workflow, relationship
or document business row is inserted directly.

| Actor / state | Discovery and projected metadata | Direct file / command behavior |
|---|---|---|
| Verified claimant; descriptive first page | Only its selected scalar field, no file metadata | Second admitted page releases its exact selected ready file |
| Same claimant; omitted file | No metadata on the selected-files page | Context and HTTP download denied; forged upload creates no document/receipt |
| Same claimant; confidential section selected by a page | Empty fields, documents and uploads | File denied because page selection cannot grant section authority |
| Same claimant; additional page role absent | Gated page absent from discovery, count zero, detail denied | Gated file denied |
| Additional page role granted then revoked | Gated page briefly admitted; open page redirects on revocation | Gated file denied again; separately admitted file stays readable |
| Verified subject-only identity, even with page role | No discovery, list rows or detail | Direct file and page upload denied |
| Unrelated external identity | No discovery, list rows or detail | Direct file and page upload denied |
| Parent identity with explicit scoped teacher grant | Admitted read-only projection under its staff authority | File readable until that actual grant is revoked |
| Wrong process or same global identity in another tenant | Zero matching rows/detail denied | Guessed file key does not cross the tenant HTTP/context boundary |

The first page's empty file selection does not veto a different admitted page's
exact release. Conversely, a document selected only by a non-admitted page cannot
be released by that page. Section read permission remains independently required.
Scoped staff authority keeps its own declared section checks; a membership label
alone grants none of it.

## Version and delivery checks

A later publication removes the old descriptive/gated pages and restricts the new
file page to reviewers. Existing record links and selected files retain their
supported pin. A new record with the same verified claimant and a newly reviewed
file is denied by its new page admission. The mixed-version file list/count contains
exactly the old admitted record, then becomes empty after that record's relationship
is revoked. Discovery and direct uploads also deny the revoked relationship.

A rendered participant form saves selected content and the authorized reviewer
releases its curated snapshot. Losing a page-only role does not revoke the still
verified recipient relationship: pending delivery succeeds under the releasing
author's fresh authority and exposes only the curated scalar content. Revoking the
relationship removes the recipient inbox as well as the file/page access. This
preserves the independent message-recipient contract rather than using page
selection as a substitute for delivery eligibility.

## Verification and limits

sprint11_participant_release_matrix_test.exs adds two maintained scenarios covering
context, query/count/discovery, actual LiveView controls, forged upload payloads and
HTTP file delivery. The focused group includes existing selected/omitted file,
participant correction/version/revocation, curated communication and tenant gates:
25 tests pass (seed 241625). Full precommit passes 327 tests (seed 355920); asset
build and whitespace checks pass. Full checks and source/log hashes are recorded in
[evidence](evidence/sprint11-participant-release-checkpoint.json).

Sprint 11 remains In progress, 1/5. T02 full supporting volumes/browser/BEAM,
remaining T03 capability/mixed-binding acceptance, T04 residual cohesion and T05
full builder recreation/recovery remain open. The earlier intermittent LiveView
token/reload observation remains unexplained. No serving migration, deployment
or destructive reset was performed.
