# Sprint 14 — Operations, data lifecycle and pilot launch readiness

[Sprint index](sprint_index.md) · [Shared roadmap](first_customer_roadmap.md) · Status: Deferred · Dependencies: Sprint 13; S12-T01 pilot contract; D-21, D-23

Goal: establish dependable operation and pass the shared customer activation checklist. Completion does not wait for the observation period or commercial outcome measured in Sprint 15.

Deferred by user direction on 2026-10-23. Preserve this scope for later customer delivery; do not execute it as the next increment. The active priority is the [school demo milestone](demo_readiness.md). Resumption requires an explicit priority decision.

## Tasks

- [ ] S14-T01 Establish recoverable, observable operation.
  - Set pilot availability expectations and recovery-time/recovery-point objectives with the owner; record deployment maintenance and manual fallback procedures.
  - Implement encrypted off-host database/file backups, access controls, retention and freshness monitoring. Perform an isolated timed restore and verify representative customer requests, files, history and pending work; prevent restored jobs from contacting real providers.
  - Document that whole-database recovery affects every tenant. A demo reset cannot use this path. Tenant-selective restore is deferred unless the agreed recovery contract requires it.
  - Monitor HTTP availability, command/refresh latency, pool wait, failed/pending deliveries, disk/storage growth and backup age. Route actionable alerts to a named owner and test an alert/recovery scenario.
  - Use redacted logs and bounded audit diagnostics, documented credential rotation and patch procedures. Rehearse deployment failure and application recovery without destructive schema rollback.
  - Reuse the bounded, authorized read models from S11-T02; this task verifies actual-host capacity rather than deferring the known in-memory-pagination architecture gap.
  - Measure representative concurrent customer work while demo traffic competes for resources on intended infrastructure, including browser/network delay and contention on one request. Measure remaining query hot spots and resource contention against agreed targets.

- [ ] S14-T02 Define customer data handling and offboarding.
  - Inventory pilot data, access, integrations, retention and processing responsibilities; document customer-facing privacy/support terms appropriate to the selected use case. RLS is not by itself a compliance claim.
  - Add an authorized operational export of requests, history and attachments, distinct from workflow-definition export. Export must respect field/section permissions, record attribution and protect temporary download artifacts.
  - Define suspension, export, retention expiry and deletion/anonymization procedures across live data, files, drafts, logs and backups. Resolve immutable history and shared global identity constraints explicitly; a manual audited procedure is acceptable for the first customer.
  - If uploads are unnecessary, disable them for the pilot. If required, implement a risk-appropriate scanning/release procedure; current structural checks and staff attestation are not antivirus.
  - Demonstrate offboarding with synthetic fixtures while preserving another organization's data. Do not automatically apply synthetic school retention settings to real customer records.

- [ ] S14-T03 Verify readiness and hand over the pilot.
  - Run mix precommit, relevant runner/deployment checks, production asset build and targeted new integration tests. Keep all test/recovery workloads isolated from customer data.
  - Record dated code revision, infrastructure, data volumes, repetitions, failures and limits for load/browser/recovery evidence. Prior local benchmarks and academic Python checks do not certify this deployment.
  - Run the agreed acceptance script with the customer administrator and operators, including onboarding, a complete request, an exception, notification failure and access recovery. Rehearse first with synthetic data.
  - Update README, operating documents, design register and sprint index to separate delivered academic capabilities from enabled customer capabilities. Resolve stale Python status statements.
  - Before live activation, record the customer's acceptance, selected data scope, operator readiness, open defects and rollback/manual fallback. No unresolved data-isolation or loss defects; any lesser limitation has an owner and explicit disposition.

## Acceptance criteria

- Off-host backups, isolated timed restore, actionable alerts and deployment-failure recovery meet documented pilot objectives. Restored jobs cannot contact real providers.
- Representative customer/demo traffic meets agreed targets on intended infrastructure, including real browser latency and same-request contention.
- Authorized operational export and audited offboarding preserve another tenant's data and account for immutable history, global identities and backup retention. Uploads are disabled or have an appropriate release procedure.
- Sprints 12–13 evidence and all items in the [shared activation checklist](first_customer_roadmap.md#shared-customer-activation-checklist) pass. Customer/operating acceptance, defect dispositions and fallback are recorded before live use.
- Record the release revision, launch handoff and the owner/date/metrics for Sprint 15. Do not claim pilot benefit before observing actual use.


## Progress

Actual start / finish: not started / not finished  
Tasks: 0/3. Status: Deferred. No implementation or customer-readiness claim is made by this plan.  
Planning date: 2026-10-21. Record dated evidence and remaining defects before changing status.

## Planning reorganization — 2026-10-21

Renumbered from Sprint 11 to 14 under D-27, preserving task suffixes, scope and local implementation notes. Sprints 09–11 now establish the reusable builder foundation before this pilot increment. Earlier evidence retains its original numbering; no remaining task is marked complete by renumbering.
