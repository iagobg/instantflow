# Sprint 07 — Integrated demonstration and delivery

[Sprint index](sprint_index.md) · Status: Planned · Dependencies: Sprint 06; D-09

Goal: reproducible, verified proof of concept.

## Tasks

- [ ] S07-T01 Assemble two-school seeds and multi-role demo covering four templates, tenant switching, independent customization, and isolation; generate the agreed multi-organization load dataset.
- [ ] S07-T02 Run authorization, concurrency, idempotency, interchange, and fault-injection gates.
- [ ] S07-T03 Measure agreed performance targets and address observed bottlenecks.
- [ ] S07-T04 Review PT-BR coverage, mobile layout, focus, keyboard access, failure states.
- [ ] S07-T05 Document deployment/limitations, exercise backup/restore, update progression evidence.

## Acceptance criteria

- Every [release gate](../design/07-verification.md) has evidence.
- Reviewer reproduces four workflows and creates/imports a fifth simple workflow.
- Performance targets are measured on a documented environment; failures are fixed or explicitly accepted.
- Recovery from missed events/retries/lost acknowledgement does not duplicate business effects.
- Setup and backup/restore succeed; no real student data is used.
- Production-readiness limitations and deferred scope are documented.
- Tenant-isolation gates run under the runtime DB role; uneven-load tests report per-organization behavior. Provisioning/suspension and shared-backup recovery are exercised without exposing or overwriting another organization's records.

## Progress

Actual start / finish: — / —  
Evidence: none yet.  
Blockers: D-09 hosting/load and earlier sprints; decision owner: product owner.  
Handoff: demonstrable platform; further production/parallel-workflow work needs new scope.
