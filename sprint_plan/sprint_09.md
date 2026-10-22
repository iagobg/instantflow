# Sprint 09 — Reusable participants, references and document policies

[Sprint index](sprint_index.md) · [Shared roadmap](first_customer_roadmap.md) · Status: Done · Dependencies: existing Sprints 01A–08; D-14, D-18–20, D-25–27

Goal: express verified relationships, external access and private document permissions through reusable process contracts, preserving the school demonstration's protections. Completion enables generated participant experiences in Sprint 10; it does not enable customer launch.

Specification: [modularity review](../docs/modularity-review.md), [process composition](../docs/process-composition.md), [permissions](../design/04-permissions.md) and [organization isolation](../design/11-organizations.md).

## Tasks

Execution order: agree and implement the minimum shared contract in S09-T05 first, then deliver T01–T03 as a working participant/document slice and verify T04. Task IDs are retained for traceability. The [builder architecture contract](../docs/builder-architecture-contract.md) governs ownership, execution, bindings and incremental recreation across all three architecture sprints.

- [x] S09-T05 Establish shared builder contracts before extending capabilities.
  - Record context ownership, permitted dependencies and the legacy adapter allowlist. Separate pure definition validation, local installation/binding resolution, runtime commands and authorized projections; generic paths must not call example-specific services after their migration.
  - Define capability descriptors and a common transaction protocol covering scoped authorization, pinned versions, revisions, lock order, guard/effect ordering, atomic rollback, receipts, audit and outbox. Implement the minimum shared boundary used by the participant slice; do not build a speculative plugin framework.
  - Specify pinned versus live bindings and configuration. Rebinding or publication must not redirect existing records' business semantics; current revocation always wins. Add publication diagnostics for missing mappings, invalid references and unsupported combinations, shared by editor and import.
  - Establish the executable recreation fixtures and dependency checks described in the architecture contract. Include a core-only baseline and the independently configured equipment service desk. Each subsequent task extends these fixtures and its cohesive module boundary instead of postponing integration to Sprint 11.

- [x] S09-T01 Define and implement organization/process-scoped participant relationships.
  - Inventory guardian, student, requester, subject and external-participant assumptions in runtime policy, enrollment, assignment, discovery, files and delivery. Define bounded participant kinds, verified relationships and explicit local bindings without selecting behavior by template key or organization slug.
  - Separate relationship verification from invitation/login identity and process administration. Administration must not imply access to protected records; unrelated participants must remain isolated.
  - Add server-authorized relationship creation, verification, revocation and audit with idempotency and revision checks. Serialize revocation against protected reads/writes and result application through the existing authorization boundary.
  - Generate additive migrations through Mix. Backfill existing guardian/student links into the reusable model, preserving IDs or audited mappings, immutable versions, files, history and local membership ownership. Rehearse populated forward migration and recovery on synthetic isolated databases; do not rewrite historical published JSON.

- [x] S09-T02 Make scoped directory references a usable definition contract.
  - Define supported reference targets and ownership for participant/subject records, field cardinality, resolution, labels, search bounds and behavior after revocation or archival. References must not grant access to the referenced record by themselves.
  - Implement directory_reference value validation and editor/form selection using authorized context queries; reject cross-process/tenant IDs, unknown targets and stale or revoked selections on submission.
  - Keep portable definitions free of local participant IDs and relationships. Export/import carries symbolic contracts; installation resolves local mappings explicitly.
  - Provide a safe compatibility path for existing school directory data. Do not replace verification with a global user dropdown or advertise the field as supported while non-null values cannot be stored.

- [x] S09-T03 Replace named-field external file rules with declared document policies.
  - Express private upload/read/release permissions against declared fields, participant relationships and section policies instead of application/document names. Preserve quarantine, bounded types/sizes, readiness guards, download authorization and attribution.
  - Revalidate ownership and permissions on upload finalization, download and retry. Revocation must remove protected UI state and prevent stale links or queued writes from restoring access.
  - Retain the existing synthetic release/scanning limits; this task does not claim production malware scanning or authorize real documents.
  - Keep legacy endpoints working through explicit compatibility mappings until the full replacement gate in S11-T05. No broad parent-role bypass or weakened confidential-section policy is acceptable.

- [x] S09-T04 Verify relationship and policy reuse independently of school names.
  - Publish independently named enrollment-like and non-school participant processes with renamed sections, fields and role keys; configure two unrelated external users through supported commands instead of developer database edits.
  - Exercise legitimate access and denial through direct IDs, search/counts, history, files, live events, exports and queued work across two processes and two organizations, including a shared identity with different local roles.
  - Test duplicate commands, stale edits, revocation/mutation races and pooled connections using actual non-owner runtime login and independent database connections for concurrency evidence.
  - Document the definition/binding contract, migration mapping, compatibility limits and operator recovery. Run mix precommit and focused participant, tenant, file and policy checks; record evidence.

## Acceptance criteria

- Shared ownership, execution and binding contracts are documented and exercised by the new vertical slice; forbidden example dependencies have a reviewed legacy allowlist. Publication errors identify the offending definition path, and new contracts agree across editor/import/runtime validation.

- An administrator configures verified participant/subject relationships and a non-null scoped directory reference without adding process-specific code or routes; permissions are enforced server-side.
- Renaming the workflow, relationship roles, sections and document fields does not change authorized behavior. Two unrelated participants cannot discover or mutate one another's data.
- Current guardian verification, confidential notes, quarantine/release and file-readiness protections survive migration. Parent/external access is never inferred solely from a broad role or administrator status.
- Cross-process/tenant association attempts fail at the context/database boundary; revocation races cannot commit unauthorized protected work after revocation wins.
- Existing published versions, tickets, files, links, history and receipts survive populated forward migration without resetting another organization. Legacy compatibility is explicit and tested.
- Shared and targeted checks pass with dated revision/environment evidence. Customer access-message transport and production scanning remain separately gated in Sprints 12–14.

## Progress

Actual start / finish: 2026-10-21 / 2026-10-22 (review corrections)  
Tasks: 5/5. Status: Done; R09-01/R09-02 corrected and verified on 2026-10-22.  
Planning date: 2026-10-21. Record dated evidence and remaining defects before changing status.  
Priority: architecture prerequisite before new domain features and pilot onboarding. Handoff: participant/reference/document contracts for Sprint 10.

### Implementation increment — 2026-10-21

The [execution/binding contract, ownership table, legacy allowlist and fixture
matrix](../docs/builder-execution.md) document S09-T05. Pure calculation validation
belongs to the catalog; binding resolution is separate from publication; shared
diagnostics identify reference/capability paths and missing local mappings.
Closed descriptors include participants. AST checks protect the boundaries.

The initial S09-T01 slice adds relationship declarations, typed editor controls,
pending/verify/revoke commands, immutable ownership, RLS, revisions, receipts,
manager-only history and revocation fencing. Tests cover independent names and
process copies; a real runtime-login race denies a save queued behind revocation.

At that initial increment S09-T01–04 remained pending. The completion increment
below supersedes those pending items; original contract evidence is preserved
separately. Guardian/document compatibility remains intentional until Sprint 11
replacement, not an unverified Sprint 09 migration.

Validation/source identity: [local evidence](../docs/evidence/sprint09-local.json).

### Completion increment — 2026-10-21

The [operator/authoring contract](../docs/participants-and-documents.md) records
ownership, reference targets, document policies, legacy mappings and recovery.
External invitations create an independent local external role without school
records or staff authority. Generic record controls add, verify and revoke pending
relationships through authorized revision/receipt commands.

Scoped participant/authenticated-subject references are searchable and editable,
stored non-null, bounded, independently authorized and fenced against revocation.
Declared private fields support configured types/sizes, separate review authority,
quarantine/readiness guards, audited receipts and durable refresh. Existing
confidential/named assignments and legacy endpoint protections pass regression.

Forward migration maps active verified, pending and revoked guardian links without
rewriting publications, records, files, receipts or history. Audited source-ID
mappings and transactional synchronization preserve old invitation/verification
behavior. Populated two-school migration plus pg_dump/restore compares historical
rows and downloads preserved private bytes with real non-owner runtime credentials.

Acceptance fixtures cover copied/renamed definitions, two unrelated invited
external users, shared identities with different local roles, two organizations,
direct IDs/search/counts/history/files/exports/live revocation, stale edits and
duplicate/revoked retries. A blank equipment desk composes verification, reference,
correction, private release, resubmission and resource settlement. Independent
connections verify queued protected saves, stale references and downloads cannot
pass revocation after it commits.

Validation: mix precommit — 224 tests, 0 failures; mix assets.build and git diff
--check passed. Source hashes and environment are in the linked evidence.
Sprint 10 follows; richer generated participant pages, full school replacement,
scale, production scanning and customer launch retain their later sprint gates.

### Review rework — 2026-10-22

The [architecture acceptance review](../docs/sprint09-architecture-review.md)
reopened subject-only configuration (T02/T04/T05) and declared parent-plus-staff
authority (T01/T04/T05). Candidate roles are now explicit and separate from data
permissions, with shared picker/create/verify eligibility and current-scope retries.
Typed authoring, schema, publication diagnostics and the operator contract agree.
Subject-only LiveView setup stores a verified non-null reference while the subject
remains unable to read/discover the record. Declared role/scoped authority applies
to parent and external memberships, including creation/discovery; pinned legacy
versions keep their compatibility protections. Maintained regressions cover grants,
revocation, foreign/disabled memberships, document review and publication pinning.

Validation: mix precommit — 231 tests, 0 failures; the reviewer's unchanged probes
— 2 tests, 0 failures. Asset build and git diff --check passed. The
[resolution record](../docs/sprint09-review-resolution.md) maps both findings to
maintained tests; refreshed source/environment evidence retains the original
pre-review completion snapshot. No historical JSON, migration or remote deployment
was needed for the corrections.
