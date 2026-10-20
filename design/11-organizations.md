# Organization isolation and foundation migration

[Design index](index.md) · D-01, D-18–20 · Updated: 2026-10-20

Multiple organizations are confirmed scope. The shared-schema persistence, global account identity, and operator-managed onboarding below are proposed defaults chosen to make that scope implementable without adding billing or a separate application per customer.

## Product boundary

An organization is an independent school/company. Departments, workflows, tickets, students, guardians, files, finance, templates, and automation are local to it. There is no organization hierarchy, shared operational record, cross-organization approval, or consolidated customer dashboard in this release.

One person may have memberships in several organizations with unrelated roles. An administrator in A may be a teacher in B; a parent in two schools has separate verified guardian relationships. Global login does not grant discovery of organizations or users. Tenant administrators manage only local membership/grants, not the person's global password, account, or other memberships.

Initial lifecycle: a restricted platform operator creates an organization and bootstraps its first administrator through an organization-bound invitation; the local administrator invites colleagues/parents. Creation and suspension are audited. Provisioning must be idempotent and recover from partial bootstrap without exposing an ownerless organization. Platform operator authority is distinct from tenant roles and does not imply business-record visibility. Support impersonation is not included.

Suspension denies tenant requests, new jobs, and result application, and disconnects relevant live sessions. Preserve records and pending intents. Resume requires revalidation, not blind replay of stale actions. Organization deletion, commercial subscriptions, public self-service onboarding, custom domains, SSO, and data-residency promises are deferred.

## Identity, invitations, and tab scope

Keep a global user/login session and unique normalized login email. Store authorization on local membership, with multiple local department/role associations as required by Sprint 02. Membership revocation in A does not revoke B. Global account/session revocation affects all organizations.

An invitation is bound to organization, recipient, allowed grants, expiry, and one-time token. For an existing account, require authentication as the invited identity before adding membership; do not replace its password or automatically link it merely because an email string matches. Existing members cannot acquire stronger grants through replay. Avoid revealing global account existence to tenant administrators or anonymous callers.

Use organization-scoped routes, for example `/o/:organization_slug/solicitacoes`. Slugs select candidates only; the server validates active membership and organization state at HTTP mount, LiveView mount, events, queries, and downloads. Missing/unauthorized scope fails closed. One available organization may auto-select after authentication; several show “Selecionar organização”. Zero active memberships show an access-unavailable page with logout and invitation handling.

Each tab/socket retains its own organization context. Switching organizations navigates to a fresh mount, clears old projections/drafts, and removes subscriptions; it never changes the target of an already rendered form in another tab. Prompt about unsaved work before voluntary switching. Browser history, direct links, reconnect, and pending responses must preserve the explicit organization. On loss of access, clear protected drafts instead of offering a save into another tenant.

## Persistent and database boundary

Use non-null organization_id on every tenant-owned row, including child rows and background records. Global exceptions are authentication identities/sessions and narrowly scoped operator metadata. A platform-owned template catalogue contains no customer data/grants and is installed by copy into the selected organization.

Composite ownership constraints must cover ticket→workflow/version/department, section→ticket, event→ticket, receipt→ticket, outbox→event/ticket, attempt→outbox, invitation→department, and later attachments, guardian links, budgets, scripts/runs. Actor attribution references global identity but authorization requires an organization-local membership; immutable historical events must survive membership revocation.

Organization-scoped uniqueness applies to names/keys and command receipts. IDs may remain globally unique internally; that never substitutes for a tenant predicate. Refuse ordinary moves of records between organizations. Return non-disclosing not-found/forbidden responses without echoing foreign labels or constraint details.

RLS is required on tenant-owned tables in the proposed baseline. Apply USING and WITH CHECK rules; absent transaction-local context denies access. Runtime roles must not be table owners, superusers, or BYPASSRLS roles. Use separate migration/operator credentials and narrow audited control-plane operations. Review policies across all tables, not just tickets; owner-mode tests can falsely appear safe. RLS defends against omitted tenant filters, not compromised application credentials that can choose arbitrary tenant context or within-tenant authorization mistakes.

The scoped repository wrapper keeps tenant queries on a checked-out connection with transaction-local context, resetting on commit/rollback. Explicitly pass scope into every async task/job. Do not use a mutable global/current tenant or rely on a connection/process dictionary inheriting scope. Cover joins, preloads, raw SQL and bulk paths with constraints and integration tests.

## Non-database boundaries

| Surface | Requirement |
|---|---|
| PubSub/Presence | Organization-qualified topics; authorize before subscribing and on refresh; never expose foreign presence/counts |
| Caches and drafts | Keys include organization and relevant user/permission revision; never reuse another organization's cached projection |
| Files | Private organization-qualified object keys; scoped metadata and authorization before upload/download; no path-based authority |
| Jobs/outbox | Persist organization; validate parent ownership; claim/run/finalize in explicit scope; no inherited or default tenant |
| Finance | Accounts, reservations, reports, and permissions remain local; no cross-organization funding |
| Imports/exports | Portable definitions only; local mappings; installation creates local ownership; imported tenant IDs never select destination |
| Python | Local script grants and run identities; fresh isolated attempts, no cross-tenant scratch/cache/input/result reuse |
| Logs/metrics | Organization correlation for operators; no payload secrets; tenant dashboards cannot expose platform-wide customer metrics |

Bound uploads, storage, queued jobs, and execution concurrency per organization, with fair dispatch so one tenant cannot starve another. Numeric quotas are deployment configuration to be measured, not unlimited promises. Keep global control-plane enumeration minimal: eligible organization IDs/status, followed by scoped work; no ordinary tenant call may invoke unrestricted scans.

## Migration from completed Sprints 00/01

Observed implementation assumptions: the identity migration has `single_organization` (`id = 1`); `Identity.organization/0`, department listing, scope lookup and lock helpers use organization 1. Users are already global; memberships already have organization/user uniqueness. Tickets/workflows have organization IDs, but several child tables inherit ownership only indirectly, receipts are unique by actor/key, and delivery topics contain only ticket IDs.

Sprint 01A must:

1. Inventory all unscoped reads/writes, seeded organization IDs, route/session assumptions, raw queries, constraints, immutable triggers, caches and workers.
2. Add forward migrations, not edits to executed migration history. Drop the singleton restriction; add slugs/status and missing ownership columns initially nullable where backfill requires it.
3. Backfill ownership from verified parents, not a blanket default. Reject inconsistent parent/event/ticket ownership. Preserve existing IDs, published definitions, event content, receipts, and outbox outcomes.
4. Coordinate backfill with append-only triggers using a controlled migration role/window; restore protections and verify them. Add composite constraints, uniqueness and NOT NULL only after validation. Never disable audit protection during ordinary traffic.
5. Introduce scoped identity/runtime/catalog/delivery access and RLS roles/policies. Use a short documented maintenance window for this small deployment rather than claiming online mixed-version compatibility. Old single-tenant application code must not run against an incompatible schema.
6. Seed a second fictional organization with overlapping human-visible names and a user who has different roles in each. Verify existing workflows/history/retries still work and cross-tenant attempts fail.

Take a backup and rehearse migration/restore. Once a second organization contains data, rollback to singleton code/schema is not safe. Prefer forward repair or full coordinated restore; never drop a tenant to make rollback pass. A full database restore affects every tenant; organization-only recovery needs a separate vetted selective procedure.

## Acceptance scenarios

- Same user, A-admin/B-teacher: A authority never applies to B, including forged event parameters and receipt replay.
- A-only user guesses B record/file/job IDs and observes no content, existence-derived counts, presence, or side effects.
- Two tabs retain distinct tenants across switching, reconnect, browser navigation, and delayed responses.
- Same idempotency key in A and B creates independent local operations, while replay within one tenant remains deduplicated.
- Database role rejects wrong-tenant reads/writes and composite cross-tenant references; pooled connection reuse after success/error leaks no context.
- Worker reuse and retries do not mix organizations; suspension/revocation racing mutation or result application fails safely.
- Editing an installed school template in A cannot change B's copy or the platform seed template.
- Migration preserves original version pins/history and rejects ambiguous backfill; rehearsed restore is documented.

All four school templates run in the primary fictional school; a second school exercises isolation, membership switching, independent template customization, and separate budgets. Final performance testing expands to a proposed ten organizations, including uneven load.
