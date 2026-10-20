# Verification and delivery

[Design index](index.md)

## Release gates

1. Four templates complete happy paths and relevant corrections/rejections.
2. Administrator creates a custom workflow without code and imports/exports a definition.
3. Parent enrollment never exposes another family's data.
4. Same-section conflicts preserve drafts; independent sections save; live views converge.
5. Competing approvals cannot double-transition or overspend.
6. Simulated results remain visibly labeled.
7. Mutations have attributable history without confidential-text leaks.
8. User-visible strings, errors, accessibility labels, and demo content are PT-BR.
9. Export/import preserves supported semantics while excluding operational data and grants.
10. Multiple organizations are isolated across identity, database reads/writes, live updates, jobs, files, imports, and metrics; a shared user receives only local roles.
11. Migration from Sprints 00/01 preserves existing data/history and establishes tenant constraints/RLS without resetting the application.

## Test strategy

Unit tests cover guards, policies, and definition validation. Database tests cover constraints/transactions. LiveView tests cover events/visibility. Browser tests cover multiple sessions, mobile, reconnect, and focus.

Concurrency tests use independent database connections, overlapping transactions, and deterministic barriers. Shared sandbox connections do not prove race safety. Required races: same/different sections, two transitions, save/approval, budgets across templates, duplicate commands, and revocation/mutation. Assert rows, balances, receipts, events, and outbox, not just UI text.

Inject crash after commit before broadcast, duplicate/out-of-order events, worker retry, lost acknowledgement, and simulated delivery failure. Verify reconciliation and no duplicate business effects.

Security tests span roles, relationships, stages, and sections: forged events, direct IDs, counts, search, files, history, editor previews, import role mapping, and event payloads. Malformed imports cover duplicate keys, oversized/deep content, unsupported versions, unknown actions, forbidden grants, and executable content.

Add organization as the outer dimension of that matrix. Use two tenants with overlapping names and differently privileged shared identities. Exercise wrong-tenant IDs, cross-tenant associations, receipt collisions, local/global revocation, suspension, two-tab switching, late events, worker reuse, and pooled connections after commit/rollback. Run raw-query RLS checks as the actual non-owner runtime role, not just migration credentials. Check missing tenant context fails closed and global control-plane access remains narrow. Future files and Python must extend this suite when their implementations land.

## Proposed performance targets

Confirm D-09 before sign-off: ten organizations with 10,000 tickets and 50 concurrent staff total; p95 accepted command response ≤ 500 ms and committed update visibility ≤ 1 second on a documented environment. Record per-organization results and test uneven load/queue flooding so a busy tenant does not starve another. Missed events reconcile within configured 30 seconds while connected. Record hardware, distribution, payloads, network, quotas, results, and exceptions. These are targets, not guarantees.

## Delivery

Document setup, migrations, seeds/reset, adapters, deployment, environment variables, backup and tested restore, limitations, and troubleshooting. No committed secrets. Demonstrate private file handling. Use synthetic data; real student-data deployment needs a separate readiness decision.

Document organization bootstrap/suspension, runtime versus migration DB roles, fair job dispatch, quota configuration, and shared-database recovery. Rehearse whole-database restore separately from any tenant-selective export/restore; do not imply one can safely substitute for the other.

A sprint is Done only with acceptance evidence, passing checks, no blocking defect, and updated progression. Passing tests does not resolve business decisions.
