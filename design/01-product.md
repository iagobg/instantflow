# Product scope

[Design index](index.md)

## Outcome

Administrators compose and publish workflows; permitted staff and parents submit requests; departments collaborate through live views; the server enforces mutations; history explains who did what.

All four school templates must use the same definitions, forms, policies, transitions, and dashboard infrastructure. Financial reservations and restricted support notes are explicit domain capabilities, not arbitrary scripts in templates.

## Proposed boundaries

- Multiple isolated organizations with invitation-based local memberships, departments, overlapping roles, and separate student/guardian directories. One login may belong to several organizations; roles never carry between them.
- Versioned workflows, typed fields, conditional transitions, stage permissions, assignments, attachments, comments, and history.
- Live tables for all processes; reusable Kanban/calendar where meaningful; responsive, keyboard-accessible flows.
- Visual editor plus portable JSON, validation, preview, and explicit publication. LLM generation happens outside the application; no AI account integration is needed.
- One active stage per ticket. Independent sections permit simultaneous work within a stage.
- Exclude general BPMN, executable rules, plugin marketplace, offline writes, collaborative rich text, real integrations, and a full school information system.
- Defer parallel branches/joins, automatic active-ticket migrations, recurring instances, and cross-process orchestration.
- Plan [isolated Python automation](10-python-automation.md) as a gated post-proof-of-concept extension. The exclusion of executable rules remains in force for Sprints 00–07. Initial Python scope is selected-input calculation with validated output, not arbitrary integrations or database access.
- Operator-managed organization creation/suspension and an explicit organization selector are in scope. Cross-organization workflows/reporting, billing, public organization signup, custom domains, support impersonation, and tenant deletion are deferred. The migration in Sprint 01A is required for this round.

## Design critique

1. Live updates cannot eliminate the interval between viewing and submitting. Promise safe conflicts and preserved drafts, not conflict-free editing.
2. Presence is approximate coordination information, not a lock or permission.
3. Unbounded customization becomes a programming language. Keep guards/actions typed, bounded, and registered.
4. Counselor notes require distinct protection across boards, history, search, files, and events.
5. Finance approval is not evidence of payment; simulations must stay explicitly labeled.
6. Budget counters require transactional reservations to prevent concurrent overspending.
7. Definition changes can strand tickets; published versions must remain immutable.
8. Valid LLM output can still encode excessive permissions or paths that bypass required approvals.

## Additional niche

Facilities/maintenance requests would exercise queues, assignment, due dates, reopening, and service metrics with less sensitive data. Keep this as a stretch template. Parallel approvals are a larger missing capability; add them only when a concrete case justifies join/cancellation semantics.

## Demonstration

Seed fictional administrator, admissions, teacher, department head, finance, operations, IT, dean, counselor, and two unrelated parent accounts. Demonstrate successful handoff, denied action, stale edit, reconnect, and failed simulated delivery followed by retry.

Run all four processes in the primary school and install independent template copies in a second fictional school. Include one person with different roles across both, an A-only user trying B's URLs, independent budgets, and two browser tabs with different organization contexts. The demonstration must prove isolation as well as modularity.

Unresolved business rules are in the [decision register](08-decisions.md).
