# Sprint 12 — Pilot scope, isolation and account access

[Sprint index](sprint_index.md) · [Shared roadmap](first_customer_roadmap.md) · Status: Planned · Dependencies: Sprint 11 architecture acceptance; existing Sprints 01A–08; D-21–23, D-27

Goal: define the first customer workflow, protect the shared demo/customer boundary and make account access recoverable. Completion enables onboarding work in Sprint 13; it does not enable customer launch.

## Tasks

- [ ] S12-T01 Agree the first workflow and measurable pilot contract.
  - Observe the owner and at least one actual operator where roles differ; document current steps, exceptions, handoffs, volumes, devices, connectivity and consequences of failure.
  - Record supported data, required integrations, expected concurrent users, baseline task duration/errors, customer success criteria and an acceptance script.
  - Identify the customer administrator, application operator/support owner, support hours, escalation route and manual fallback. Record a BRL price or explicit pilot terms and a review date; manual commercial administration is acceptable.
  - If printing is essential, specify target printer/connection, order amendments/cancellation, retry/reprint labeling and uncertain delivery handling. A database receipt does not prove a physical ticket printed exactly once. Do not declare the workflow supported until the actual device path is tested.

- [ ] S12-T02 Enforce demo/customer boundaries and resource limits.
  - Implement the shared-database controls in the [roadmap](first_customer_roadmap.md#shared-database-decision) using the existing organization lifecycle and scoped repositories. Generate additive migrations through Mix; preserve existing organizations and publications.
  - Review default-enabled features and remove academic execution permissions from the customer host. Explicitly record final hosting/runtime choices.
  - Test direct URLs, altered identifiers, files, history, counts, presence, exports, jobs and pooled connections across demo/customer boundaries with a real non-owner runtime login.
  - Exercise scoped demo reset, effect denial, quota exhaustion and permission changes without changing customer records or stopping their workflow. Test contaminated/global demo identity memberships fail the operating preflight.

- [ ] S12-T03 Make account access supportable.
  - Select and implement the real email transport for access messages in this sprint, using Req for HTTP integrations and the existing durable delivery foundation. Keep credentials server-side; enforce demo/sample effect denial at dispatch, bounded retries, failure visibility and ambiguous-outcome handling. Verify with designated consenting test recipients. Sprint 13 extends this transport to workflow notifications.
  - Add real invite delivery and password recovery using expiring single-use digested tokens, non-enumerating responses, bounded attempts and delivery abuse controls.
  - Rate-limit login and recovery; revoke sessions appropriately after recovery/security changes and clean up expired sessions/tokens.
  - Support resend/revoke invitations, member deactivation and administrator succession without leaving an organization accidentally unmanageable. Recovery must not change local roles or other memberships.
  - Require stronger authentication for privileged access: implement admin MFA or document and test an equivalent restricted-access control before the pilot; do not claim MFA exists today.
  - Verify token replay/expiry, cross-account misuse, access revocation and recovery end to end. Existing-account invitations must preserve credentials and unrelated memberships.

## Acceptance criteria

- A real candidate workflow has a documented baseline, supported scope, devices/integrations, success measures, review date, support owner and manual fallback. The restaurant table-service workflow is selected from user-reported discovery; direct observation, baseline measurements and operator acceptance remain required.
- Shared-database demo controls pass non-owner isolation, scoped reset, quota and effect-denial checks. Academic uploaded-code execution is disabled/drained on the customer host or separately reassessed before customer data is introduced.
- Invitations and recovery work through a real tested access-message transport, including expiration/replay, revocation, throttling and failure recovery. No demo/sample delivery reaches real recipients.
- Privileged access and administrator succession have verified controls. Recovery cannot change tenant permissions.
- Run mix precommit and focused identity, tenant and delivery checks; record evidence and defects. Customer activation remains gated by Sprints 13–14.


## Progress

Actual start / finish: not started / not finished  
Tasks: 0/3. Status: Planned. No implementation or customer-readiness claim is made by this plan.  
Planning date: 2026-10-21. Record dated evidence and remaining defects before changing status.

## Restaurant discovery update — 2026-10-21

The user selected table-order service as the pilot workflow and reported Windows notebook + USB POS-80, separate Cozinha/Parrilla papers, waiter/table/time attribution, checkout/table reuse and daily totals. Menu setup and selectable products precede service. [Confirmed inputs, implementation evidence and open decisions](../docs/restaurant-pilot.md) distinguish user-reported discovery from actual operator observation. S12-T01 remains unchecked: baseline measurements, terms, success targets and direct acceptance are still required. Other Sprint 12 gates remain open.

## Planning reorganization — 2026-10-21

Renumbered from Sprint 09 to 12 under D-27, preserving task suffixes, scope and local implementation notes. Sprints 09–11 now establish the reusable builder foundation before this pilot increment. Earlier evidence retains its original numbering; no remaining task is marked complete by renumbering.
