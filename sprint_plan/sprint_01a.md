# Sprint 01A — Multi-organization foundation migration

[Sprint index](sprint_index.md) · Status: Done · Dependencies: Sprint 01; D-01, D-18–20

Goal: migrate the existing single-organization implementation into a verified multi-organization foundation before expanding permissions/live collaboration in Sprint 02.

Specification: [architecture](../design/02-architecture.md) and [organization isolation/migration](../design/11-organizations.md).

## Tasks

- [x] S01A-T01 Inventory tenant assumptions and prepare/rehearse forward migrations, ownership backfills, composite constraints, receipt uniqueness, RLS runtime roles/policies, and backup recovery.
- [x] S01A-T02 Separate global login from local membership scope; add organization-bound invitations, operator provisioning/suspension, route-based selection, and PT-BR organization UI.
- [x] S01A-T03 Scope existing catalog/runtime/identity commands, reads, joins, receipts, and audits; enforce transaction-local tenant access and revalidated membership without organization-1 fallbacks.
- [x] S01A-T04 Scope live topics, refreshes, outbox dispatch/retry and connection reuse; add per-organization bounded job scheduling and migration-compatible synthetic seeds.
- [x] S01A-T05 Verify isolation with two organizations, differently privileged shared user, real runtime DB role, independent connections, migration preservation, and documented operator recovery.

## Acceptance criteria

- Existing Sprint 01 fixtures, version pins, history, receipts, and pending deliveries survive forward migration; no destructive reset is required.
- Organization A and B have independent templates, tickets and membership; A-only users cannot read, mutate, subscribe to, or infer B data through covered application paths.
- A shared user's roles remain local, and membership revocation in one organization does not remove the other membership.
- Existing-account invitations require proof of account ownership and never overwrite credentials; invite replay cannot add grants.
- Two tabs remain bound to their own organizations; switching/reconnect cannot redirect an old command to another organization.
- Tenant RLS denies missing/wrong context under the non-privileged runtime DB role; composite FKs reject cross-tenant associations, including raw SQL writes.
- Same receipt key in two organizations is independent; retries inside one remain idempotent. Worker/connection reuse cannot carry stale tenant scope.
- Suspension blocks commands, job starts, and result application and clears affected sessions. No default tenant is selected on failure.
- A second tenant cannot be destroyed to accommodate rollback. Backup/restore and forward-repair limitations are documented and rehearsed.
- Required precommit and targeted tenant-isolation checks pass with evidence; detailed department/section capabilities continue in Sprint 02.

## Progress

Actual start / finish: 2026-10-20 / 2026-10-20  
Evidence:
- Forward migration: ../priv/repo/migrations/20261020200807_isolate_organizations.exs. Original migrations are unchanged.
- Scoped unit of work, RLS and startup gate: ../lib/instantflow/tenant.ex and ../lib/instantflow/runtime_database.ex; identity, catalog, runtime and delivery contexts enforce local ownership.
- Operator provisioning/suspension/resume/bootstrap recovery: ../lib/instantflow/organizations, ../lib/mix/tasks. PT-BR organization picker and auth hooks preserve tab context.
- Full required checks: mix precommit passes with 51 tests; asset build passes; repeatable two-school seeds preserve prior records and credentials.
- runtime_role_test.exs uses an actual non-owner login in a separate disposable database and independent connections for suspension/command/result races, raw SQL RLS/FK tests, transaction reset, bounded scheduling and operator recovery. Ordinary regression fixtures retain a privileged sandbox for preparing data; this distinction is explicit.
- tenant_isolation_test.exs and organization_live_test.exs cover local roles/receipts/templates, foreign IDs, invitation ownership proof, revocation, workers and independently bound live tabs.
- ../scripts/rehearse_01a.py passes against the actual pre-01A backup and a fresh legacy fixture containing pending delivery: original values preserved, multitenant backup restored, singleton rollback refused without deleting the second school. Private recovery databases/backups remain under ignored local tooling.
- Browser: the shared Ana account selects two schools; Horizonte administration stays local while a second tab shows collaborator access in Aurora. Existing request #1 retains its approval, version and history.
- Runbook and inventory: ../docs/organizations-operations.md. CI configuration is updated; remote CI execution is not claimed.

Limits: separate operator CLI invalidations use reconnect/30-second live revalidation; a full restore affects all organizations, and production cutover/per-tenant recovery remains outside this sprint. Detailed department/section capabilities continue in Sprint 02.  
Defaults: D-18–20 adopted under authorization to proceed from Sprint 01A, without deviations. No blockers recorded.  
Handoff: isolated foundation for Sprint 02 and all subsequent school slices.
