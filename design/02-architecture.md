# Architecture and data model

[Design index](index.md)

## Proposed architecture

A modular Phoenix monolith using LiveView, Ecto, and PostgreSQL. Context functions own authorization and business rules. LiveViews render authorized projections and call commands. JavaScript may manage focus, panel expansion, draft warnings, and pending indicators; it cannot authoritatively approve, spend, change stages, or grant access.

| Context | Responsibility |
|---|---|
| Identity | Accounts, sessions, invitations, departments, grants, revocation |
| Directory | Minimal students and verified guardian relationships |
| WorkflowCatalog | Definitions, validation, publication, import/export |
| WorkflowRuntime | Tickets, sections, assignments, guarded transitions |
| Access | Record, field, action, file, and history policies |
| Collaboration | Authorized dashboards, subscriptions, advisory presence |
| Files | Private uploads, quarantine/scan state, downloads |
| Finance | Allocations, reservations, postings, reversals |
| Delivery | Durable outbox, simulated adapters, retries |
| Audit | Attributable events and restricted history |

Start with one deployment and database. No microservices or persistent actor per ticket. Database constraints remain authoritative across application instances.

## Persistent entities

| Entity | Invariants |
|---|---|
| Organization | One configured organization; no tenant switcher |
| User, membership, department, role grant | Active status and revocable permissions |
| Student, guardian link | Explicit verified relationship |
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
| Command receipt | Actor, operation, key, request digest, durable result |

Use relational columns for scope, stages, revisions, and frequent filters. Extensible section values may use JSONB validated against their pinned definition. Use integer minor units and explicit currency for money. Store instants in UTC; render in configured timezone; keep date-only values separate.

Organization ownership provides a boundary and future migration aid; enforce consistent ownership through scoped queries and appropriate composite keys. This does not constitute production multi-tenancy.

## Command boundary

Commands take authenticated actor, target, operation, expected revisions, and idempotency key. Never trust client identity, role, or organization claims.

Within one short database transaction:

1. Re-read and lock relevant authorization facts and business rows in a documented global order.
2. Validate permissions, revisions, stage, pinned definition, values, and guards.
3. Apply changes, increment revisions, record history, persist command receipt, and insert outbox intent.
4. Commit, then request live refresh. Durable outbox processing covers a crash after commit.

Repeated keys with the same payload return the previous outcome subject to current authorization. Reusing a key with another payload fails. Database uniqueness resolves simultaneous duplicates.

Revocation and mutations coordinate on the same authorization locks. A check outside the transaction is insufficient. External calls never hold database locks. Delivery is at least once, with deduplication and explicit retry/unknown states; do not promise exactly-once external delivery.

## Files and operations

Private storage, authorization per download, bounded file sizes/types, and quarantine until validation completes. File readiness can guard transitions. Use fictional demo data.

Logs carry correlation IDs, not student/support text. Observe command latency, conflicts, denied actions, connections, outbox lag, and failed deliveries. Pin compatible maintained dependencies during bootstrap.

## Primary references

- [Ecto.Multi](https://ecto.hexdocs.pm/Ecto.Multi.html): grouping transactional operations.
- [LiveView security](https://hexdocs.pm/phoenix_live_view/security-model.html): authorization of live interactions.
- [PostgreSQL locking](https://www.postgresql.org/docs/current/explicit-locking.html): locks and deadlocks.
