# Sprint 01 — Workflow runtime

[Sprint index](sprint_index.md) · Status: Done · Dependencies: Sprint 00; D-08, D-14

Goal: execute validated, versioned workflows through guarded commands.

Historical scope: delivered against the single-organization foundation. [Sprint 01A](sprint_01a.md) adds tenant scope, migration, and isolation before Sprint 02. The completed criteria below do not establish multi-organization readiness.

## Tasks

- [x] S01-T01 Implement definition schema, typed fields/guards, validation, immutable versions.
- [x] S01-T02 Implement tickets, sections, revisions, transition history, constraints.
- [x] S01-T03 Build transactional commands, authorization hooks, receipts, and global lock ordering.
- [x] S01-T04 Add durable outbox and deterministic simulated success/failure adapters.
- [x] S01-T05 Exercise approval, correction, rejection, cancellation, and retry with a minimal fixture.

## Acceptance criteria

- Invalid graphs/types cannot publish; existing tickets remain pinned.
- Forged stage fields cannot bypass transitions; missing required fields block advancement.
- Duplicate command keys do not duplicate effects; payload mismatch fails.
- Failed transactions leave no partial ticket/history/outbox changes.
- Recovery after commit-before-broadcast preserves business consistency.

## Progress

Actual start / finish: 2026-10-20 / 2026-10-20  
Evidence:
- Definition validation, publication and local bindings: ../lib/instantflow/workflow_catalog.ex and ../lib/instantflow/workflow_catalog/definition.ex.
- Versioned tickets, independent section revisions, guarded commands and immutable history/receipts: ../lib/instantflow/workflow_runtime.ex and ../priv/repo/migrations/20261020184948_create_workflow_runtime.exs.
- Durable polling outbox and deterministic success/fail-once/failure simulations: ../lib/instantflow/delivery.ex and ../lib/instantflow/delivery/worker.ex.
- PT-BR demonstration screens: ../lib/instantflow_web/live/requests_live.ex and ../lib/instantflow_web/live/request_live.ex.
- Passing validation: mix precommit, 37 tests, assets build, all migrations rolled back/reapplied on the test database, repeatable development seeds.
- Browser evidence: teacher submitted request #1; reviewer approval was blocked by a failed simulated notification; retry succeeded on attempt 2, then approval completed. Both the request and history remained consistent.

Limits: database tests use Ecto sandbox; independent-connection races and multi-session reconciliation belong to Sprint 02. Directory/file type names are reserved and non-null values fail closed until their authorized contexts exist. The initial form renderer exercises the text-based approval fixture; the full editor and type-specific controls follow in Sprint 03. No real provider is called.  
Blockers: none. D-08/D-14 adopted as implementation defaults under authorization to proceed with the plan; see the decision register.  
Handoff: stable schemas/commands for live collaboration.
