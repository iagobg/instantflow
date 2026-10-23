# Sprint 13 — Organization onboarding and first workflow

[Sprint index](sprint_index.md) · [Shared roadmap](first_customer_roadmap.md) · Status: Deferred · Dependencies: Sprint 12; Sprints 09–11 architecture acceptance; D-22, D-27

Goal: let an invited administrator configure and complete the selected process, with understandable collaboration and the integrations it requires. Use synthetic acceptance fixtures until Sprint 14 launch readiness is accepted.

Deferred by user direction on 2026-10-23. Preserve this scope for later customer delivery; do not execute it as the next increment. The active priority is the [school demo milestone](demo_readiness.md). Resumption requires an explicit priority decision.

## Tasks

- [ ] S13-T01 Implement resumable assisted organization onboarding.
  - Keep initial provisioning operator-controlled. Create the initial administrator through an authenticated invitation, without shared/default passwords or granting operator access to the web process.
  - Wizard: organization name/timezone → choose or compose a supported process → map people/departments/responsibilities → try a clearly marked sample → review and activate → invite the team.
  - Save server-side progress with tenant ownership and revision checks; tolerate retries, interrupted sessions and two administrators editing setup. Creation/publication must be idempotent and auditable.
  - Reuse definition validation and immutable publication. Resolve all required mappings before activation. Explain incompatible role combinations, including prohibited finance self-approval, instead of bypassing policy for small teams.
  - Preview each role using synthetic data and the real authorization rules; no impersonation into actual customer records. Sample records must be identifiable, excluded from operational totals and prohibited from real effects by backend controls.
  - Clearly show incomplete setup, validation errors and next actions. Reopening the wizard must not republish or alter existing pinned requests silently.

- [ ] S13-T02 Make the chosen workflow understandable and resilient in daily use.
  - Use the generated pages, participant/projection contracts and reusable blocks verified in Sprints 09–11; do not introduce restaurant-specific routes or process-key screen dispatch.
  - Provide one maintained starter template and common configuration controls with plain labels: fields, who can see/edit them, approvals and next steps. Keep advanced configuration optional.
  - Show responsible person/department, permitted next action, saved/unsaved state, pending commands, connection state and actionable conflict comparison.
  - Implement a scoped, expiring draft recovery strategy for navigation/reload, with explicit save/reapply and fresh permission checks. Do not auto-submit recovered drafts or store protected drafts indiscriminately in browser storage. Remove revoked data and document retention.
  - Verify concurrent independent-section edits, same-section conflicts, stale approval, lost acknowledgements and reconnect. Include a real two-browser run, mobile layout and keyboard operation on the customer's actual devices.

- [ ] S13-T03 Deliver the integrations that the pilot actually requires.
  - Reuse the access-message provider/transport delivered in S12-T03 and extend it to necessary workflow notifications; use Req for HTTP integrations. Keep provider credentials outside templates and client state.
  - Extend durable delivery with explicit simulated/real modes, scoped recipients, bounded retries, provider identifiers, failure visibility and operator recovery. Recheck organization mode and eligibility at dispatch, not only enqueue.
  - Minimize message contents; confidential details remain behind authenticated access. Prevent test/demo/sample notifications from reaching real recipients.
  - Handle ambiguous external outcomes explicitly. Use provider idempotency where supported; do not promise exactly-once effects merely because internal commands are idempotent.
  - Verify the reported Windows notebook/USB POS-80 path with the actual device: split destination papers, attribution, added orders, cancellation notices, reprint labels and uncertain physical outcomes. Browser print requests alone do not satisfy this check.
  - Implement only S12-T01-required non-email integrations. Test failure, timeout, duplicate callbacks/retries, cancellation and manual recovery. Real external acceptance tests use designated consenting recipients/devices during implementation.

## Acceptance criteria

- The wizard resumes after interruption and concurrent administrator edits without duplicate organizations/publications or lost configuration. Required mappings and sample effect restrictions are enforced server-side.
- An administrator completes a sample request using a maintained template and understandable role/configuration controls. Existing pinned requests remain unchanged by configuration edits.
- Two-browser collaboration, draft recovery, stale approvals, mobile/keyboard behavior and revoked access pass on the agreed devices.
- Required workflow integrations pass timeout, duplicate/retry, cancellation and operator-recovery scenarios. The selected restaurant workflow requires actual Windows notebook/USB POS-80 acceptance for split Cozinha/Parrilla papers, table/responsible person/time attribution, reprints and cancellation notices under the finalized S12-T01 contract.
- Run mix precommit, assets build and focused onboarding/LiveView/integration checks. Record evidence; completion is product readiness for Sprint 14, not permission to launch.


## Progress

Actual start / finish: not started / not finished  
Tasks: 0/3. Status: Deferred. No implementation or customer-readiness claim is made by this plan.  
Planning date: 2026-10-21. Record dated evidence and remaining defects before changing status.

## Authorized restaurant implementation increment — 2026-10-21

At the user's request, the reusable catalog/resource-session/batch context and restaurant operational view were implemented locally ahead of full Sprint 12 completion, using synthetic fixtures. See [walkthrough, architecture and evidence](../docs/restaurant-pilot.md). Menu setup, fast entry, split tickets, checkout, daily summaries and estimated product consumption cover part of S13-T02/T03. This does not mark either task complete: resumable organization onboarding, durable draft recovery, actual-device acceptance and dependent launch gates remain open. No live deployment is authorized by this increment.

## Process-model correction — 2026-10-21

The user clarified that organization-owned process definitions must generate URLs and UI, rather than selecting hard-coded school/restaurant screens. The local increment now implements a declarative interface.pages contract, generic process routes/renderer, editor-controlled pages and ordered blocks, symbolic block access and per-process operational data. See docs/process-composition.md for evidence and the explicit legacy adapter gap. S13 tasks remain unchecked: this foundation does not complete onboarding, durable draft recovery, all legacy capability migrations, customer acceptance or printer acceptance.

## Planning reorganization — 2026-10-21

Renumbered from Sprint 10 to 13 under D-27, preserving task suffixes, scope and local implementation notes. Sprints 09–11 now establish the reusable builder foundation before this pilot increment. Earlier evidence retains its original numbering; no remaining task is marked complete by renumbering.
