# Organization operations and Sprint 01A migration

The application now uses global accounts/sessions with independent local memberships. Routes, projections, commands, receipts, history, outbox records and live topics carry explicit organization ownership. No application path falls back to organization 1. Historical migrations and the original school's IDs are preserved.

## Credentials and setup

The HTTP application starts only `Instantflow.Repo`, using the non-owner `instantflow_runtime` login. Startup rejects a superuser, BYPASSRLS/CREATEROLE role, table owner, or a different login. Tenant access uses a checked-out transaction with `SET LOCAL ROLE` and transaction-local `instantflow.organization_id`; nested access to another organization fails. Context/role restoration also covers sandbox and nested transactions. RLS uses both USING and WITH CHECK; foreign keys and ownership triggers enforce parent/child consistency.

`Instantflow.OperatorRepo` is not in the application supervision tree. Migration/CLI commands start it explicitly. Local settings are `MIGRATION_PGUSER`, `MIGRATION_PGPASSWORD`, and optionally `MIGRATION_DATABASE`; production operators use `OPERATOR_DATABASE_URL`. Do not supply operator credentials to a deployed web process. The operator needs permission to create/grant the runtime role and migrate the schema. Provision that authority independently in production.

```sh
# Local demonstration defaults: PostgreSQL on 127.0.0.1:55432
docker compose up -d --wait
mix ecto.create -r Instantflow.OperatorRepo
mix ecto.migrate -r Instantflow.OperatorRepo
# Production requires an explicit RUNTIME_DB_PASSWORD. Local demo has a documented default.
mix instantflow.db_roles
export DEMO_PASSWORD='choose-a-local-demo-password'
mix run priv/repo/seeds.exs
mix phx.server
```

The runtime's `DATABASE_URL` must authenticate as `instantflow_runtime` in production. `RUNTIME_DB_PASSWORD` configures its login via the operator task; keep it aligned with the serving URL. For local development `PGUSER` defaults to `instantflow_runtime`; `RUNTIME_DB_PASSWORD` defaults to `instantflow-runtime-local-only`. The Compose superuser password uses the separate `MIGRATION_PGPASSWORD` default `instantflow-local-only`.

## Forward migration / maintenance window

1. Stop old web traffic and workers. This is not a mixed-version or online migration.
2. Take a custom-format `pg_dump` using operator credentials and record the source version. Keep backups private, outside Git.
3. Rehearse against an isolated restore first, then apply `mix ecto.migrate -r Instantflow.OperatorRepo` in the maintenance window. An ambiguous or inconsistent parent chain aborts the migration transaction.
4. Run `mix instantflow.db_roles` with operator credentials; deploy the new code with runtime credentials. Verify account selection, both organizations, pending delivery and local permission checks before restoring traffic.

The migration removes the singleton constraint, adds slug/status, backfills ownership through verified parent joins, and derives existing receipt operations through their referenced history revision. It temporarily disables only append-only triggers inside the controlled migration transaction, reinstates them, and then adds NOT NULL, composite keys, immutability triggers and RLS. It never rewrites published definitions, user credentials, receipt digests, IDs, history values or delivery outcomes. The original organization receives the stable slug `horizonte` during this one-time backfill; this is not a runtime default.

## Recovery rehearsal

```sh
# Requires PostgreSQL client binaries on PATH, or PG_BIN pointing to their directory.
python3 scripts/rehearse_01a.py
# Rehearse from your pre-01A custom-format backup instead of the synthetic fixture:
python3 scripts/rehearse_01a.py --backup /private/path/pre-01a.dump
```

The script creates uniquely named recovery databases, compares every original column value before/after migration, adds a second school, dumps/restores the migrated database, compares every restored row, and verifies rollback refusal leaves both schools present. It never targets or drops the serving database. The recovery databases and private backup remain for operator inspection. The default synthetic fixture includes version pinning, history, a receipt and a pending notification.

**Sprint 01A is forward-only.** After a second organization exists, use a reviewed forward repair or stop all traffic and coordinate a full backup restore. A whole-database restore affects every organization and may discard work since the backup. Restore into an isolated environment, provision the required roles, verify the data, and explicitly plan cutover; this sprint does not implement production cutover or per-organization recovery. Never delete another tenant to satisfy old rollback code.

## Operator provisioning and lifecycle

```sh
mix instantflow.organizations provision escola-nova 'Escola Nova' admin@nova.example bootstrap-001 --operator 'Operador autorizado'
mix instantflow.organizations suspend escola-nova suspend-001 --operator 'Operador autorizado'
mix instantflow.organizations resume escola-nova resume-001 --operator 'Operador autorizado'
```

Provisioning atomically creates the organization, first department, bootstrap invitation and immutable operator audit event. It does not create an active privileged person or a support impersonation account. The bootstrap invitation is shown once; replay of the same key/content returns the same organization without another grant or token. Changed content fails. A transaction failure leaves no ownerless organization. Invalid inputs do not create partial records. A disabled system identity attributes platform invitations and cannot log in.

If the operator loses a bootstrap token or it expires before the first administrator joins, run `mix instantflow.organizations reissue-bootstrap SLUG EMAIL KEY --operator NAME`. This audited, idempotent operation issues a new code and expires previous bootstrap invitations atomically. It is refused after an administrator membership has existed, so it cannot override local membership revocation. It never overwrites a global password. Existing-account recipients must sign in as the invited account before accepting; existing memberships are never upgraded or reactivated by an invitation. Initial new-account acceptance uses the same one-time code path. Tenant administrators receive no global account lookup or password-management endpoint.

Suspension locks the organization row exclusively. Commands and job result transactions acquire its share lock first, so suspension coordinates with work already in flight. Suspended organizations are excluded from dispatch and selection, and pending intents remain stored. Resumption rechecks current organization state and local authorization. Tenant session/projection invalidation preserves access to other memberships and global login. Same-node invalidation is immediate; the independent operator CLI and a missed PubSub event are covered by reconnect and a 30-second live revalidation timer. Do not assume a separate CLI process shares the web node's in-memory PubSub.

## Scheduling and boundaries

Live topics include organization and ticket IDs and only carry invalidations. Subscriptions require an authorized projection and recheck global session, membership and status on refresh. Switching uses a full organization mount, warns about dirty request forms and never changes another tab's target. Loss of local access redirects and clears the affected view.

Outbox processing always takes persisted organization plus message identity; a foreign message ID cannot be claimed. Each dispatcher pass processes at most `delivery_batch_per_organization` messages per organization (default 20), granting every active organization a batch before another poll. Commands enforce `max_pending_deliveries_per_organization` (default 1000) under an organization-specific advisory lock; exhaustion rolls back ticket, history and receipt writes. Result application and result invalidations remain in the same tenant. These are demo configuration bounds, not measured performance guarantees. Storage/upload quotas belong to the later Files slice; there is no upload path in this sprint.

Runtime RLS does not defend against compromised application credentials choosing their own tenant setting, and does not replace local business permissions. The narrow SECURITY DEFINER functions expose only active membership choices, token-bound invitation routing and eligible organization IDs for dispatch; there is no ordinary unscoped tenant scan API. Credential identities and global sessions are the deliberate global exceptions. Audit events contain organization and actor attribution without passwords, invitation tokens or business field contents.

## Verification evidence — 2026-10-20

The implementation inventory covered: the singleton organization constraint and sequence; hardcoded identity/catalog/runtime predicates; indirectly owned version/section/event/receipt/outbox/attempt rows; actor-only receipt uniqueness; anonymous versus authenticated invitation acceptance; root-only routes/session assumptions; ticket-only PubSub topics; unscoped dispatcher reads/retries; credential/logging configuration; and seed/reset/CI rollback assumptions. Each was replaced by the scoped paths and forward-only operational procedures above. Historical migrations remain unchanged.

- Existing regression tests moved to explicit tenant routes. Their sandbox fixture connection uses the owner role to prepare fixtures; scoped application calls explicitly execute under the runtime role.
- `runtime_role_test.exs` additionally creates a separate disposable database and uses an actual non-owner login, not an owner-mode RLS approximation. It checks role flags/ownership, missing/wrong context, raw SQL composite-FK rejection, context reset on the same connection after commit/rollback, independent connections racing suspension against commands and result application, bounded scheduling and operator idempotency.
- `tenant_isolation_test.exs` checks local roles, templates, guessed IDs, receipts, invitation ownership proof, local revocation and worker scope.
- `organization_live_test.exs` checks two local tabs, forged destination data, revocation clearing and no-membership selection.
- Rehearsal passed from the actual pre-01A demo backup and the synthetic legacy fixture. Multitenant restore and forward-only rollback refusal passed. Private snapshots/backups remain under ignored `.local/`.
- Browser smoke: shared `admin@escola.example` sees both schools, has administration in Horizonte and only collaboration in Aurora; the Horizonte team tab remained bound while Aurora was open separately.

Detailed department/section grants, broad simultaneous editing races and the full school templates remain in their planned sprints. No real student data, provider calls, billing, self-service onboarding, support impersonation or Python execution is introduced.
