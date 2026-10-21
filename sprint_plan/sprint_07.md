# Sprint 07 — Integrated demonstration and delivery

[Sprint index](sprint_index.md) · Status: Done · Dependencies: Sprint 06; D-09

Goal: reproducible, verified proof of concept.

## Tasks

- [x] S07-T01 Assemble two-school seeds and multi-role demo covering four templates, tenant switching, independent customization, and isolation; generate the agreed multi-organization load dataset.
- [x] S07-T02 Run authorization, concurrency, idempotency, interchange, and fault-injection gates.
- [x] S07-T03 Measure agreed performance targets and address observed bottlenecks.
- [x] S07-T04 Review PT-BR coverage, mobile layout, focus, keyboard access, failure states.
- [x] S07-T05 Document deployment/limitations, exercise backup/restore, update progression evidence.

## Acceptance criteria

- Every [release gate](../design/07-verification.md) has evidence.
- Reviewer reproduces four workflows and creates/imports a fifth simple workflow.
- Performance targets are measured on a documented environment; failures are fixed or explicitly accepted.
- Recovery from missed events/retries/lost acknowledgement does not duplicate business effects.
- Setup and backup/restore succeed; no real student data is used.
- Production-readiness limitations and deferred scope are documented.
- Tenant-isolation gates run under the runtime DB role; uneven-load tests report per-organization behavior. Provisioning/suspension and shared-backup recovery are exercised without exposing or overwriting another organization's records.

## Progress

Actual start / finish: 2026-10-21 / 2026-10-21  
Evidence: [release-gate matrix](../docs/release-gates.md), [reproducible four-template/fifth-workflow demo](../docs/demo.md), [performance measurements](../docs/performance.md), [deployment and limits](../docs/deployment.md).  
Verification: mix precommit passed 136 tests; production assets and release build passed; runtime-role release startup/login/two digested assets returned HTTP 200. Populated isolated whole-database recovery and legacy forward migration/rollback refusal passed with the final schema.  
Load: verified 10 schools, 10,000 tickets and 50 concurrent staff. Equal mixed lifecycle: 4,000 commands, p95 39.522 ms command / 830 ms final-state visibility. Uneven mixed lifecycle: 5,200 commands, p95 40.481 ms / 817 ms; each school and measured operation met the local targets. Polling and durable refresh batching fixed observed visibility failures while preserving attempts/retry semantics. Backend timings exclude browser/network latency; raw reports and baseline failures are linked in the measurement report.  
UX: targeted desktop/mobile PT-BR and keyboard smoke; skip link, support-save persistence, private-section visibility, shared-identity switching and direct-ID denial verified. File controls gained explicit PT-BR labels. Professional accessibility/device certification remains outside local evidence.  
Blockers: none for the synthetic demonstration. D-09 defaults adopted for local measurements; production hosting, real data, off-host backups and operating objectives remain separately documented readiness work.  
Handoff: Sprints 00–07 complete; Sprint 08 remains Proposed / gated by the user's explicit 2026-10-21 decision. No customer Python execution was added.
