# Sprint 01 — Workflow runtime

[Sprint index](sprint_index.md) · Status: Planned · Dependencies: Sprint 00; D-08, D-14

Goal: execute validated, versioned workflows through guarded commands.

## Tasks

- [ ] S01-T01 Implement definition schema, typed fields/guards, validation, immutable versions.
- [ ] S01-T02 Implement tickets, sections, revisions, transition history, constraints.
- [ ] S01-T03 Build transactional commands, authorization hooks, receipts, and global lock ordering.
- [ ] S01-T04 Add durable outbox and deterministic simulated success/failure adapters.
- [ ] S01-T05 Exercise approval, correction, rejection, cancellation, and retry with a minimal fixture.

## Acceptance criteria

- Invalid graphs/types cannot publish; existing tickets remain pinned.
- Forged stage fields cannot bypass transitions; missing required fields block advancement.
- Duplicate command keys do not duplicate effects; payload mismatch fails.
- Failed transactions leave no partial ticket/history/outbox changes.
- Recovery after commit-before-broadcast preserves business consistency.

## Progress

Actual start / finish: — / —  
Evidence: none yet.  
Blockers: resolve D-08 and D-14 before Ready; decision owner: product owner.  
Handoff: stable schemas/commands for live collaboration.
