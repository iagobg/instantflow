# Sprint 03 — Editor and portable templates

[Sprint index](sprint_index.md) · Status: Done · Dependencies: Sprint 02; D-15 (confirmed)

Goal: administrators create, review, exchange, and publish workflows without source changes.

## Tasks

- [x] S03-T01 Build draft cloning/comparison, revision-aware saves, stage/transition graph and keyboard list.
- [x] S03-T02 Add typed forms, permissions, assignments, bounded guards/actions, and configurable views.
- [x] S03-T03 Finalize versioned JSON Schema/capability catalogue and shared structural/semantic validator.
- [x] S03-T04 Implement authorized export, draft-only import, local mappings, diff/role preview, explicit publication.
- [x] S03-T05 Finalize PT-BR LLM guide/examples and verify round trips, malformed imports, and editor-created fixtures.

## Acceptance criteria

- Administrator creates a simple workflow without code.
- Organization A's editor, role preview, import/export, and bindings cannot reference B resources, even for a user with both memberships. Installing the same template in both creates independent versions and configuration.
- A cloned template accepts new fields/stages; publishing version 2 preserves active version-1 tickets.
- Invalid graph, reference, type, capability, or unauthorized mapping cannot publish.
- Role preview exposes no real records; concurrent draft edits conflict safely.
- Editor/export/import/editor preserves supported semantics; import has no business side effects.
- Export contains no student/ticket data, secrets, or actual grants; unresolved local mappings block publication.
- A template generated from the guide validates as a reviewed draft using the delivered schema.
- All drag actions have keyboard equivalents and use guarded commands.
- The capability catalogue distinguishes current support from planned Python automation. Unknown Python actions/inline code remain rejected; no script editor or runner ships in this sprint. A later explicit format extension may bind reviewed script versions without weakening current validation.

## Progress

Actual start / finish: 2026-10-20 / 2026-10-20  
Evidence: `mix precommit` passed: **92 tests, 0 failures**, warnings-as-errors, unused lock check and formatting; `mix assets.build` passed. D-15 explicitly confirmed by the user during this increment.  
Blockers: none for Sprint 03.  
Handoff: general-purpose definition tooling, exercised by the school demonstration templates. Sprint 04 remains Planned pending its own guardian/file decisions; no external-participant or private-file behavior was added here.

### Delivery evidence

- T01: [draft context](../lib/instantflow/workflow_catalog/templates.ex), [editor](../lib/instantflow_web/live/template_live.ex), [draft/revision tests](../test/instantflow/workflow_catalog/templates_test.exs). Diagram plus keyboard-native item controls; no drag-only operations. Draft and base-version comparisons prevent stale saves/publications.
- T02: [typed authoring](../lib/instantflow/workflow_catalog/authoring.ex), [configured view projection](../lib/instantflow/workflow_catalog/views.ex), [permission and pinning tests](../test/instantflow/workflow_catalog/views_test.exs), [LiveView tests](../test/instantflow_web/live/templates_live_test.exs). Money, dates/instants, booleans and multiple choices work in request forms, including clearing selections. Directory/file values still fail closed.
- T03: [format 1.0 schema](../priv/templates/workflow-1.0.schema.json), [capabilities](../priv/templates/capabilities-1.0.json), [schema-driven validator](../lib/instantflow/workflow_catalog/schema.ex), [semantic validator](../lib/instantflow/workflow_catalog/definition.ex). Unknown properties/actions, Python, executable content, bad references and malformed graphs fail closed. Legacy published spelling normalizes on clone/export without mutating stored versions.
- T04: [import/export](../lib/instantflow/workflow_catalog/interchange.ex), [catalogue UI](../lib/instantflow_web/live/templates_live.ex), [tenant-isolation and side-effect assertions](../test/instantflow/workflow_catalog/templates_test.exs). JSON paste and file upload create unmapped drafts; explicit targets, local-only mappings, definition-only role preview, export preview, SHA-256 source digest and append-only publication audit. Historical definitions with formerly unchecked view properties cannot export those properties.
- T05: [PT-BR guide](../design/workflow_authoring_guide.pt-BR.md), [simple](../design/examples/simple_approval.json) and [typed](../design/examples/typed_approval.json) examples, [round-trip/malformed-import tests](../test/instantflow/workflow_catalog/interchange_test.exs). The same definition supports authoring, review and publication; schema vocabulary coverage prevents silent validation drift.
- [Independent runtime-connection tests](../test/instantflow/runtime_role_test.exs) overlap saves and publications behind a row-lock barrier: one save revision, one published version/event, old ticket pin preserved. Raw non-owner queries deny absent/foreign tenant context; composite ownership constraints reject cross-tenant draft ancestry; published drafts and audit events reject mutation.
- Browser verification at `http://localhost:4000/o/horizonte/modelos/1`: cloned the existing published demo, added a money field, saved/reloaded and confirmed the selected editor stays on the saved field. The reviewable demo draft is unpublished; existing published workflows were preserved.
- Local forward migration applied. Legacy migration/restore rehearsal passed using new databases `instantflow_rehearsal_old_c97819d05b18` and `instantflow_rehearsal_restore_c97819d05b18`; all original values, multitenant restore and rollback refusal passed. Backup: ignored `.local/backups/rehearsed-multiorg-c97819d05b18.dump`.

Operating details and limits: [template editor](../docs/template-editor.md). General browser automation beyond the documented local check, mobile viewport testing and load benchmarks are not claimed by this evidence.
