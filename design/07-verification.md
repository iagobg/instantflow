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

## Test strategy

Unit tests cover guards, policies, and definition validation. Database tests cover constraints/transactions. LiveView tests cover events/visibility. Browser tests cover multiple sessions, mobile, reconnect, and focus.

Concurrency tests use independent database connections, overlapping transactions, and deterministic barriers. Shared sandbox connections do not prove race safety. Required races: same/different sections, two transitions, save/approval, budgets across templates, duplicate commands, and revocation/mutation. Assert rows, balances, receipts, events, and outbox, not just UI text.

Inject crash after commit before broadcast, duplicate/out-of-order events, worker retry, lost acknowledgement, and simulated delivery failure. Verify reconciliation and no duplicate business effects.

Security tests span roles, relationships, stages, and sections: forged events, direct IDs, counts, search, files, history, editor previews, import role mapping, and event payloads. Malformed imports cover duplicate keys, oversized/deep content, unsupported versions, unknown actions, forbidden grants, and executable content.

## Proposed performance targets

Confirm D-09 before sign-off: 10,000 tickets, 50 concurrent staff; p95 accepted command response ≤ 500 ms; p95 committed update visibility ≤ 1 second on a documented environment. Missed events reconcile within configured 30 seconds while connected. Record hardware, dataset, payloads, network, results, and exceptions. These are targets, not measured guarantees.

## Delivery

Document setup, migrations, seeds/reset, adapters, deployment, environment variables, backup and tested restore, limitations, and troubleshooting. No committed secrets. Demonstrate private file handling. Use synthetic data; real student-data deployment needs a separate readiness decision.

A sprint is Done only with acceptance evidence, passing checks, no blocking defect, and updated progression. Passing tests does not resolve business decisions.
