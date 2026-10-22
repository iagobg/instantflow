# First customer roadmap

[Sprint index](sprint_index.md) · Status: Planned · Planning date: 2026-10-21

Goal: serve one real organization through one supported workflow and evaluate actual use. This roadmap coordinates the architecture prerequisites in Sprints 09–11 and customer delivery in Sprints 12–15; it is not itself a sprint. It preserves the original pilot scope and does not authorize deployment, purchases, external communications or customer-data processing now.

## Delivery sequence

| Sprint | Independently reviewable outcome | Depends on |
|---|---|---|
| [09](sprint_09.md) | Shared builder contracts, reusable participants, scoped references and document policies | Existing foundation; D-25–28 |
| [10](sprint_10.md) | Generated external pages, configured dashboards, finance and curated communications | 09 |
| [11](sprint_11.md) | Explicit operational contracts, bounded authorized reads and full builder recreation acceptance | 09–10 |
| [12](sprint_12.md) | Defined pilot, demo boundaries and recoverable account access | 11 architecture gate |
| [13](sprint_13.md) | Resumable onboarding and a usable, integrated workflow | 12; verified common builder |
| [14](sprint_14.md) | Recoverable operations, data lifecycle and customer launch acceptance | 13 |
| [15](sprint_15.md) | Measured pilot outcome and continue/change/stop decision | 14 and an actual observation period |

Sprints remain dependency-ordered increments without duration estimates. Sprint 15 is an observation/review increment: it must not keep completed engineering sprints open while waiting for customer use. Architecture Sprints 09–11 take priority over feature expansion. Their recreation gate is a prerequisite for pilot engineering; it does not authorize live use. Operational design and recovery objectives should be considered during Sprint 12 discovery; their full implementation and launch acceptance belong to Sprint 14.

## Product boundary

- Start with operator-assisted provisioning and organization-local guided setup. Public signup, automatic subscriptions, a marketplace, and broad integration coverage are deferred.
- The user selected restaurant table service: a single operator on a Windows notebook with USB POS-80, menu setup, split kitchen/parrilla papers, table/responsible person/time attribution, checkout/table reuse, daily totals and estimated consumption. These are confirmed reported needs, not customer sign-off; S12-T01 still owns direct observation, measurable scope and acceptance. Implement them through common process contracts and reusable blocks rather than a separate restaurant application.
- Prefer one low-sensitivity administrative process. Do not import student incidents, guardian records, health information or other sensitive demonstration scenarios into customer operation by default.
- Reuse the workflow runtime, immutable publication, scoped grants, command receipts and outbox. Keep implementation and validation in PT-BR for customer-facing flows.
- Sprints 09–11 must prove editor/import-based recreation of the four school examples, restaurant service and an additional non-school process. Participant/directory/document policies, projections and finance/communication surfaces remain bounded reusable capabilities; arbitrary code, full inventory, deposits/refunds and broad currency expansion are not implied.
- The wizard must get an administrator to a successful first request; merely creating an organization is not completion.

## Shared database decision

A demo organization and customer organizations may share one production PostgreSQL database and schema. Dedicated databases are not a prerequisite for this pilot. Credentials authenticate a global user; organization memberships, authorization, runtime-role RLS and ownership constraints provide the data boundary. Shared credentials must never also have a customer membership or operator authority.

Shared storage does not mean zero interference: connection pools, CPU, storage, queues, migrations, outages and whole-database restores remain shared. Measure and bound this exposure. A separate database on the same VM alone does not remove host-level risk.

Required controls before co-hosting:

- Persist an operator-controlled organization mode distinguishing demonstration from customer operation. Organization administrators cannot change it or bypass its effect restrictions.
- Demo identities have demo-only memberships; use distinct identities for customer administrators. Do not reuse the current synthetic seed identities across the boundary. Demo accounts cannot invite themselves or others into customer organizations.
- Demo content is synthetic, clearly labeled, and never copied from customer records. Shared demo accounts, if offered, explicitly have no expectation of privacy from other demo visitors; onboarding previews use private scoped fixtures instead.
- Demo organizations cannot send real email, invoke customer integrations, or execute uploaded Python. Enforce the mode at dispatch/result boundaries as well as in the UI. Invalid or absent mode must not enable external effects.
- Add bounded demo users/requests/storage/jobs and abuse limits; verify a busy demo tenant does not make the customer workflow unusable.
- Demo refresh/reset is an explicit operator-only, tenant-targeted procedure with ownership checks and an audit trail. It must preserve global identities and records belonging to other organizations. Never run global seeds, database reset, or whole-database restore to refresh the demo. Preserve the existing refusal to seed production.
- Shared-host uploaded Python from Sprint 08 was accepted for a private synthetic university deployment only. Proposed pilot default: disable and drain execution on any host serving real customer data, including demo execution, and verify no running/queued workload can later apply results. Keeping scripting requires a separate production boundary decision and acceptance evidence; a second database is not sufficient isolation.
- Development, automated tests, load generators and destructive restore rehearsals still use isolated disposable databases/environments with synthetic data. A co-hosted product demo is not a staging environment.


## Shared customer activation checklist

The Sprint 11 architecture gate and Sprints 12–14 must pass their own acceptance criteria before live pilot activation. Wizard activation in Sprint 13 publishes configuration; it does not by itself authorize real customer use. Sprint 15 evaluates use after launch and is not a pre-launch prerequisite.

- The Sprint 11 recreation/preservation gate passes with generated participant experiences, configured views, explicit operational contracts and bounded authorized reads; remaining architectural limitations match the claimed pilot scope.
- The chosen workflow, actual devices, data scope, required integrations, baseline metrics, review date and operating owners are recorded in S12-T01.
- An invited administrator can resume setup and complete a first request without developer database edits or hidden grants.
- Demo sessions cannot discover customer data, create customer memberships, send real notifications, execute scripts or exceed agreed resource limits. Demo reset cannot change customer records.
- Account recovery, revocation, required integrations, export, offboarding and interruption recovery have evidence. No simulated effect is represented as a real completion.
- The operator can detect and recover failures within agreed objectives, with off-host backups and an isolated restore rehearsal.
- Customer and operator acceptance, open-defect disposition and manual fallback are recorded in S14-T03 before launch. There are no unresolved data-isolation or data-loss defects.
- All checks use the actual release revision and documented environment; academic evidence is retained with its original limits.

## Scope tracking

The [architecture acceptance contract](../docs/builder-architecture-contract.md) adds explicit ownership: shared execution/binding/dependency rules and incremental fixtures → S09-T05; bounded query interface → S10-T02 with scale completion in S11-T02; explicit correction resets → S10-T03; composed-effect rollback, publication diagnostics and mixed-version compatibility → S11-T03. The additional equipment service desk is a synthetic builder acceptance fixture, not expanded pilot scope. The initial S09-T05 implementation is evidenced below; later requirements retain their own acceptance gates.

Sprint 09 is Done, 5/5, with verified participant/reference/document contracts and populated legacy migration/recovery. See the [operator contract and acceptance evidence](../docs/participants-and-documents.md). Sprints 10–11 and customer-delivery tasks retain their own unchecked gates. The restaurant increment and 190-test modularity pass remain historical baseline evidence. Completed Sprints 00–08 retain their original history; Sprint 09 does not imply customer launch readiness.

The D-27 reorganization inserts higher-priority architecture work and renumbers the unstarted pilot increments without dropping scope:

| Previous sprint/tasks | Current sprint/tasks | Preserved responsibility |
|---|---|---|
| 09 / S09-T01–03 | [12](sprint_12.md) / S12-T01–03 | Pilot scope, isolation and access |
| 10 / S10-T01–03 | [13](sprint_13.md) / S13-T01–03 | Onboarding, daily use and integrations |
| 11 / S11-T01–03 | [14](sprint_14.md) / S14-T01–03 | Operations, data handling and launch |
| 12 / S12-T01 | [15](sprint_15.md) / S15-T01 | Post-launch evaluation |

Earlier evidence and dated decisions may retain previous sprint/task identifiers; use this mapping rather than rewriting their historical source hashes. Before the earlier four-sprint split, the original combined Sprint 09 tasks T04–06/T07–09/T10 became the present S13-T01–03/S14-T01–03/S15-T01 respectively. Access-message transport stays in S12-T03, before S13 workflow notifications.

Architecture finding ownership is explicit: participant relationships and directory references → S09-T01/T02; external file policies → S09-T03; external projections → S10-T01; dashboards/calendar → S10-T02; finance → S10-T03; curated messages → S10-T04; operational assumptions → S11-T01; bounded reads → S11-T02; contract compatibility → S11-T03; cohesive editor/command extraction → S11-T04; populated preservation and full recreation → S11-T05. Durable drafts → S13-T02; physical POS-80 acceptance → S13-T03; recovery/throttling → S12-T03; backup/export/offboarding/launch → Sprint 14.

Provider/device choices, support/commercial terms, retention and recovery objectives remain implementation inputs with named owners. Resolve them before the dependent work or activation; do not invent customer requirements. Public self-service, automated billing and broad integrations remain deferred.
