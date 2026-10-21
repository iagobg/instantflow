# Sprint 02 — Permissions and live collaboration

[Sprint index](sprint_index.md) · Status: Done · Dependencies: Sprint 01A; D-13

Goal: safe collaboration through authorized live tables and section forms.

## Tasks

- [x] S02-T01 Implement organization-local role/department/relationship/stage policies and restricted projections on the migrated tenant boundary.
- [x] S02-T02 Build tables, filters, scoped counts, subscriptions, reconnect/reconciliation.
- [x] S02-T03 Add section editors, advisory presence, pending states, conflict reconciliation.
- [x] S02-T04 Implement revocation invalidation and transactional authorization coordination.
- [x] S02-T05 Verify real overlapping database transactions and multi-session scenarios.

## Acceptance criteria

- Same-section writes cannot silently overwrite; losing authorized draft is preserved.
- Independent sections save without unnecessary conflicts.
- Competing transitions commit once; changed reviewed content requires renewed review.
- Revoked users cannot refresh protected data or mutate records; protected UI clears.
- Duplicate/out-of-order events and disconnects converge.
- Counts, history, presence, and events do not reveal hidden records.
- A shared user's different organization roles never combine; concurrent tabs, membership revocation, and live events remain scoped. Retain Sprint 01A isolation regression coverage while adding finer policies.

## Progress

Actual start / finish: 2026-10-20 / 2026-10-20  
Evidence:
- [Local grants and coordination](../lib/instantflow/access.ex), [tenant lock order](../lib/instantflow/tenant.ex), and [additive migration](../priv/repo/migrations/20261020205338_add_local_grants_and_authorization_coordination.exs): paired role/department grants, tenant RLS/composite FKs, attributable grant changes, shared command/read gate and exclusive revocation gate. Existing versions and records remain unchanged.
- [Policy and projections](../lib/instantflow/workflow_runtime/policy.ex): no administration bypass, restricted section/history/delivery projections, current local grants, and finance-sensitive self-approval denial. D-13 adopted as the proposed implementation default; no override capability added.
- [Request table](../lib/instantflow_web/live/requests_live.ex): explicit filters, 25-row pages, authorized counts, immutable ID ordering, subscription before fetch, minimal authorized invalidations, reconnect and periodic reconciliation.
- [Section editor](../lib/instantflow_web/live/request_live.ex): independent drafts and observed revisions, compare/reapply/discard, refreshed clean sections, preserved unrelated drafts, renewed transition review, stable command keys, pending feedback, and permission-loss cleanup. Advisory presence exposes only currently authorized names/sections and expires after 45 seconds without a heartbeat.
- [Real database races](../test/instantflow/runtime_role_test.exs): independent non-owner connections with observed database lock barriers, same/different sections, duplicate commands, competing approvals, save/transition conflicts, membership revocation and grant revocation. Assertions cover values, revisions, receipts, history and outbox effects; no sleeps or shared-sandbox claims of race safety.
- [Access regressions](../test/instantflow/access_test.exs), [multi-session editor tests](../test/instantflow_web/live/collaboration_live_test.exs), team form tests and existing tenant/tab isolation regressions: restricted history, counts, invalidation recipients, presence expiry, recovered drafts, protected draft removal, and shared identities with separate organization grants.
- Required checks: mix precommit passes with 72 tests; assets build passes. Browser checks cover the narrow-width request table and a real server stop/restart: controls disable offline, an unsaved draft recovers without submitting, and the committed revision remains unchanged. A lost-save-acknowledgement test also proves that recovered form metadata cannot replace the receipt key or duplicate an effect. Temporary verification drafts were discarded.
- Migration/restore rehearsal passes with legacy records, a second school and a local grant preserved. The rehearsal's synthetic explicit-ID fixtures now advance their sequences correctly; supplied backups are never rewritten. The current forward-only rollback refuses without deleting either school.

Limits: exact counts currently evaluate local policy over all candidate summaries before pagination; the proposed Sprint 07 load target has not been measured. Drafts live only in the current tab/process and LiveView recovery; a full browser reload can discard them. Missed permission invalidations reconcile within 30 seconds while connected; every read and command reauthorizes independently. No parent, file, or Python execution features were added. See [operating notes](../docs/collaboration.md).

Blockers: none recorded.  
Handoff: reusable access and live UX for Sprint 03's visual editor and interchange.
