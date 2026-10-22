# Architecture and data model

[Design index](index.md)

## Proposed architecture

The [builder architecture contract](../docs/builder-architecture-contract.md) refines the planned Sprints 09–11 target: context ownership and dependency direction, capability execution, pinned/live binding lifetime, publication diagnostics and incremental cross-domain recreation. Existing school-specific services below are migration sources and compatibility paths; their presence does not establish that generated processes are already independent of them.

A modular Phoenix monolith using LiveView, Ecto, and PostgreSQL. The workflow core is sector-independent; domain modules and templates supply specialized records and terminology. Context functions own authorization and business rules. LiveViews render authorized projections and call commands. JavaScript may manage focus, panel expansion, draft warnings, and pending indicators; it cannot authoritatively approve, spend, change stages, or grant access.

| Context | Responsibility |
|---|---|
| Organizations | Tenant lifecycle, settings, membership selection, isolation boundary |
| Identity | Accounts, sessions, invitations, departments, grants, revocation |
| Directory (school demonstration module) | Minimal students and verified guardian relationships; not required by the workflow core |
| WorkflowCatalog | Definitions, validation, publication, import/export |
| WorkflowRuntime | Tickets, sections, assignments, guarded transitions |
| Access | Record, field, action, file, and history policies |
| Collaboration | Authorized dashboards, subscriptions, advisory presence |
| Files | Private uploads, quarantine/scan state, downloads |
| Finance | Allocations, reservations, postings, reversals |
| Delivery | Durable outbox, simulated adapters, retries |
| Audit | Attributable events and restricted history |

Use a shared PostgreSQL database/schema and Phoenix deployment serving multiple isolated organizations. An organization is the tenant boundary; departments are subdivisions, not tenants. No cross-organization workflows, shared operational records, or consolidated tenant dashboards in this round. Database-per-tenant deployment remains a future option, not the initial design. See [organization isolation and migration](11-organizations.md).

Isolation has three layers: mandatory server-validated organization scope in contexts, composite database ownership constraints, and PostgreSQL row-level security (RLS) for tenant-owned rows. RLS supplements business authorization; it does not decide department, section, or transition permissions. No microservices or persistent actor per ticket are required.

The optional [Python extension](10-python-automation.md) is an exception requiring a separately isolated execution service. Reuse transactional enqueueing, not execution inside the current demo delivery transaction. Short claim/finalize transactions surround execution outside database locks; no customer code runs in the Phoenix host process or inherits its credentials.

## Persistent entities

| Entity | Invariants |
|---|---|
| Organization | Independent tenant with stable ID/slug, name, timezone, active/suspended status |
| User, session | Global authentication identity; does not carry organization-wide authority |
| Membership, department, role grant | Tenant-owned; one membership per user/organization with organization-local grants and department associations |
| Student, guardian link (school demonstration) | Explicit verified relationship in the school domain module |
| Workflow, workflow version | Stable identity; editable draft; immutable published version |
| Stage, transition, section, field definitions | Stable keys within a version |
| Ticket | Pinned version, stage, requester, subject, assignment, state revision |
| Ticket section | Typed values, independent revision, classification |
| Attachment | Parent section, private object key, readiness metadata |
| Comment | Author and explicit visibility |
| Transition/audit event | Actor, action, timestamp, command identity, visibility |
| Budget account | Currency, period, allocation, transactional balance control |
| Reservation/posting | Positive amount, unique operation identity, reversal linkage |
| Outbox/delivery attempt | Durable intent, deduplication key, attempt/result |
| Command receipt | Organization, actor, operation, key, request digest, durable result |

Use relational columns for scope, stages, revisions, and frequent filters. Extensible section values may use JSONB validated against their pinned definition. Use integer minor units and explicit currency for money. Store instants in UTC; render in configured timezone; keep date-only values separate.

Every tenant-owned row, including workflow versions, sections, events, receipts, outbox messages, and attempts, carries a non-null organization_id. Composite foreign keys enforce matching organization across parent/child references; independent valid IDs are not enough. Uniqueness for workflow keys, department names, and idempotency receipts is organization-scoped. Organization ownership is immutable through ordinary application commands.

Users and authentication sessions are global exceptions; credential records are never exposed through tenant queries. Memberships link users to organizations. Tenant-visible people come from authorized local memberships, not a global user directory. Guardian/student records, finance accounts, files, scripts, and grants belong to exactly one organization. A user belonging to two schools does not merge their children, records, roles, or budgets.

Tenant database access runs through a scoped unit of work on one checked-out connection: set transaction-local tenant context from an authenticated/authorized server scope, query, then commit/rollback. Missing context fails closed. Do not use session-level tenant settings on pooled connections or assume process-local state propagates to tasks. Enforce RLS for reads and writes using a non-owner, non-superuser runtime role without BYPASSRLS; migration credentials are separate. Test the actual runtime role. Joins, preloads, raw queries, bulk operations, and workers must preserve scope. A small audited control-plane path handles login, organization selection, and provisioning; it is not a generic unscoped query escape hatch.

## Command boundary

Commands take a validated scope (user, organization, membership), target, operation, expected revisions, and idempotency key. The URL selects a candidate organization, not authority. Revalidate active organization/membership; never silently default to organization 1 or another membership. Fetch targets inside the scope, including on receipt replay. Idempotency uniqueness includes organization, actor, operation, and key, with a digest binding the target/payload.

Within one short database transaction:

1. Re-read and lock relevant organization/membership authorization facts and business rows in a documented global order compatible with suspension/revocation.
2. Validate permissions, revisions, stage, pinned definition, values, and guards.
3. Apply changes, increment revisions, record history, persist command receipt, and insert outbox intent.
4. Commit, then request live refresh. Durable outbox processing covers a crash after commit.

Repeated keys with the same payload return the previous outcome subject to current authorization. Reusing a key with another payload fails. Database uniqueness resolves simultaneous duplicates.

Revocation and mutations coordinate on the same authorization locks. A check outside the transaction is insufficient. External calls never hold database locks. Delivery is at least once, with deduplication and explicit retry/unknown states; do not promise exactly-once external delivery.

## Files and operations

Private storage, authorization per download, bounded file sizes/types, and quarantine until validation completes. File readiness can guard transitions. Use fictional demo data.

Storage keys, cache keys, PubSub/Presence topics, delivery jobs, audits, and future Python runs include organization identity. Workers validate persisted organization ownership and re-establish scope for each job; no fallback tenant. A minimal dispatcher may enumerate eligible organization IDs from control-plane metadata, then claim jobs under each tenant's RLS context with bounded fair scheduling. Suspension stops new work and invalidates sessions/results without silently discarding queued business intents.

Restore shared backups into an isolated recovery environment. A per-organization restore/export must preserve ownership and references without overwriting other tenants; do not promise independent tenant restore from a whole-database backup. Initial provisioning/suspension uses a restricted audited operator path; billing, self-service signup, domains, support impersonation, and tenant deletion are deferred.

Logs carry correlation IDs, not student/support text. Observe command latency, conflicts, denied actions, connections, outbox lag, and failed deliveries. Pin compatible maintained dependencies during bootstrap.

## Primary references

- [Ecto.Multi](https://ecto.hexdocs.pm/Ecto.Multi.html): grouping transactional operations.
- [LiveView security](https://hexdocs.pm/phoenix_live_view/security-model.html): authorization of live interactions.
- [PostgreSQL locking](https://www.postgresql.org/docs/current/explicit-locking.html): locks and deadlocks.
- [Ecto tenancy with foreign keys](https://ecto.hexdocs.pm/multi-tenancy-with-foreign-keys.html): explicit scoping and matching parent/child ownership.
- [PostgreSQL row security](https://www.postgresql.org/docs/16/ddl-rowsecurity.html): policies and privileged-role bypass behavior. Implementation must verify this under the project's PostgreSQL 16 runtime.
