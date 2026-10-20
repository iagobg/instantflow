# Sprint 03 — Editor and portable templates

[Sprint index](sprint_index.md) · Status: Planned · Dependencies: Sprint 02; D-15

Goal: administrators create, review, exchange, and publish workflows without source changes.

## Tasks

- [ ] S03-T01 Build draft cloning/comparison, revision-aware saves, stage/transition graph and keyboard list.
- [ ] S03-T02 Add typed forms, permissions, assignments, bounded guards/actions, and configurable views.
- [ ] S03-T03 Finalize versioned JSON Schema/capability catalogue and shared structural/semantic validator.
- [ ] S03-T04 Implement authorized export, draft-only import, local mappings, diff/role preview, explicit publication.
- [ ] S03-T05 Finalize PT-BR LLM guide/examples and verify round trips, malformed imports, and editor-created fixtures.

## Acceptance criteria

- Administrator creates a simple workflow without code.
- A cloned template accepts new fields/stages; publishing version 2 preserves active version-1 tickets.
- Invalid graph, reference, type, capability, or unauthorized mapping cannot publish.
- Role preview exposes no real records; concurrent draft edits conflict safely.
- Editor/export/import/editor preserves supported semantics; import has no business side effects.
- Export contains no student/ticket data, secrets, or actual grants; unresolved local mappings block publication.
- A template generated from the guide validates as a reviewed draft using the delivered schema.
- All drag actions have keyboard equivalents and use guarded commands.

## Progress

Actual start / finish: — / —  
Evidence: none yet.  
Blockers: confirm D-15 before Ready; decision owner: product owner.  
Handoff: common definition tooling for school templates.
