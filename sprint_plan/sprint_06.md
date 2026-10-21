# Sprint 06 — Confidential incident collaboration

[Sprint index](sprint_index.md) · Status: Done · Dependencies: Sprint 05; D-06

Goal: urgent triage and independent confidential sections.

## Tasks

- [x] S06-T01 Configure mobile reporting, urgency, triage, assignment, resolution.
- [x] S06-T02 Implement disciplinary/support sections with explicit grants.
- [x] S06-T03 Add restricted dashboard and accessible urgency announcements.
- [x] S06-T04 Add curated simulated guardian communication and closure guard.
- [x] S06-T05 Verify concurrent dean/counselor work and data-leak scenarios.

## Acceptance criteria

- Authorized office sees urgent report; unauthorized sessions receive no detail.
- Dean and counselor concurrently save separate permitted sections.
- Teacher/parent/unassigned users cannot retrieve private support notes through any projection.
- Same-section conflicts preserve authorized drafts; revocation clears protected content.
- Closure requires resolution and configured simulated communication outcome.
- Urgency works without color; mobile/keyboard interaction remains usable.
- A counselor assigned in one school gains no access in another; presence, urgency announcements, files, and derived summaries never cross tenant boundaries.

## Progress

Actual start / finish: 2026-10-21 / 2026-10-21  
Evidence: mix precommit passed: 133 tests, 0 failures; assets built. Forward migration and repeatable two-school seeds verified.  
Blockers: none for the synthetic demonstration; D-06 adopted under continuation authorization. Production incident-response and real guardian messaging are separate scope.  
Handoff: fourth template and full permission stress case.

## Delivery evidence

- T01/T03: [incident template](../priv/workflows/incident.json), [restricted dashboard](../lib/instantflow_web/live/incidents_live.ex), [scope context](../lib/instantflow/incidents.ex). Factual mobile-friendly reporting, text urgency, polite atomic status announcement, authorized counts/filtering and stage workflow. Reporter sees only own report; dean sees locally authorized triage; unassigned counselor/parent sees no incident details.
- T02: [assignment context](../lib/instantflow/collaboration/assignments.ex), [runtime](../lib/instantflow/workflow_runtime.ex), [policy](../lib/instantflow/workflow_runtime/policy.ex), [private documents](../lib/instantflow/private_documents.ex). Named active local assignees with fixed role/department grants; manager-only audit and independent support/discipline sections. No dean/admin bypass of confidential notes/files. Revoke remains possible after closure.
- T04: Resolution and deliberately curated message/contact precede simulated notification. First delivery fails; closure stays blocked until authorized retry succeeds. Teacher/counselor projections omit confidential message/history/outbox. No real guardian delivery or implicit parent incident access.
- T05: [context tests](../test/instantflow/incidents/incidents_test.exs), [LiveView tests](../test/instantflow_web/live/incidents_live_test.exs), [definition tests](../test/instantflow/incidents/definition_test.exs), [independent runtime-role tests](../test/instantflow/runtime_role_test.exs). Cross-section saves both commit; same-section race has one conflict; a queued counselor write fails after exclusive assignment revocation commits. Shared counselor identity in another school gains no record/file/presence/count access; wrong-school assignment fails. Live private draft revocation redirects and drops content, hidden history/summaries/presence do not disclose notes, and quarantined uploads require separate release.

[Setup, walkthrough and precise limits](../docs/incidents.md). Mobile/keyboard fields use semantic shared controls; integrated browser/device/focus review belongs to Sprint 07. No exhaustive accessibility, emergency-response, clinical, disciplinary or production student-data certification is claimed.
