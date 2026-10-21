# Sprint 08 — Isolated Python calculations

[Sprint index](sprint_index.md) · Status: Done · Dependencies: Sprint 07; D-16, D-17

Goal: demonstrate one synthetic trip calculation through an asynchronous gVisor runner on the owner's private university VPS. This optional extension does not reopen Sprints 00–07.

Specification: [Custom Python automation](../design/10-python-automation.md). [Operations and walkthrough](../docs/python-calculations.md). [Readiness assessment](../docs/python-readiness.md).

## Scope and readiness decision

On 2026-10-21 the user selected the synthetic trip calculator, retained uploaded scripts and specified Oracle Ampere A1 ARM / Ubuntu / 4 OCPUs / 24 GB RAM, also hosting Phoenix/PostgreSQL. They explicitly chose “Same VPS with gVisor; revise the host-separation requirement for the university demo.”

This authorizes the shared-host implementation. A sandbox escape could reach the app/database VM; that academic limitation is documented, with synthetic data and privately gated access only. The operating default is the project owner, using the supplied shutdown/recovery/patch runbook. No extra paid infrastructure is introduced.

The implementation gate is resolved for this scope. Execution remains disabled by default. The activation/completion gate requires real ARM host verification of gVisor, external limits, network/resource denial, cleanup, emergency shutdown and recovery. No ordinary-container or test-adapter result substitutes for this evidence.

## Tasks

- [x] S08-T01 Validate use case and threat model; evaluate isolation/runtime hosting and record the go/no-go decision.
  - Evidence: user-approved academic topology, bounded trip fixture, threat model and conditional implementation-go / activation-no-go in the readiness assessment.
- [x] S08-T02 Implement immutable script catalogue, separate review/activation permissions, schemas, synthetic fixtures, and versioned reference-only workflow bindings.
  - Evidence: catalogue/contract/import tests; script upload/review LiveView; database immutability/RLS; independent author/reviewer/binder/executor/source grants.
- [x] S08-T03 Implement bounded isolated runner and dispatch protocol, deny network/credentials, enforce external resource limits and cleanup, add emergency disablement.
  - Evidence: real ARM64 gVisor isolation and service reports, authenticated Unix transport, measured cgroup limits, emergency removal, watchdog cleanup and startup orphan reconciliation. No Docker or operator credentials enter Phoenix.
- [x] S08-T04 Implement durable run intents, leases/fencing, independent workers, validated idempotent result application, waiting-stage freshness guards, PT-BR status/retry UX.
  - Evidence: lifecycle/UI tests and independent non-owner database connections for concurrent claims and duplicate finalization. No Python call occurs in a workflow transaction or refresh worker.
- [x] S08-T05 Verify hostile workloads, confidentiality, races/recovery, import boundaries, measured limits, and documented operating procedures.
  - Evidence: hostile-workload checks on the A1, broker kill/restart recovery, real deployed-release calculation and worker lease/fence recovery across two disposable synthetic organizations; operations and local-merge deployment procedures updated.

## Acceptance criteria

- An authorized reviewer activates an immutable version after synthetic fixtures pass; a configured transition queues it and applies only allowed output fields.
- Uploaded source runs only inside gVisor, outside Phoenix and database transactions. The workload receives no application credentials or arbitrary record access.
- Network/host-resource denial, resource exhaustion, fresh scratch and complete cleanup pass on the actual host, with evidence limits stated.
- Scripts cannot directly approve, spend, send email, alter permissions or change stages. Computed fields cannot target finance-effect inputs.
- Revocation, disablement, cancellation, suspension and input/stage changes prevent unauthorized or stale application.
- Duplicate dispatch, expired leases, retries and late results cannot apply a logical result twice. Required-result guards fail closed.
- Slow calculations do not block refresh delivery or hold ticket locks; PT-BR status/retry guidance remains available.
- Workflow imports carry references only, without source activation or inherited local grants.
- The owner can disable dispatch/results, terminate/reconcile workloads, patch images and inspect bounded authorized diagnostics.
- Organization-local scripts, grants, bindings, snapshots, outputs and diagnostics remain confined. Broker/application quotas constrain a busy organization independently.

## Progress

Actual start / finish: 2026-10-21 / 2026-10-21  
Evidence: [local verification](../docs/evidence/sprint08-local.json), catalogue/contract/runtime/HTTP/LiveView tests, independent-connection runtime-role race test, Python broker/example tests.  
Tasks: 5/5; acceptance criteria passed for the approved synthetic academic scope.  
Operating default: project owner; gVisor and broker installed on the private VPS, application deployed through GitHub Actions after local merge, Unix transport and durable execution explicitly enabled.  
Evidence: [ARM isolation](../docs/evidence/sprint08-a1-isolation.json), [broker recovery](../docs/evidence/sprint08-a1-service.json), [application recovery](../docs/evidence/sprint08-a1-application.json), [live enablement](../docs/evidence/sprint08-a1-deployment.json). No remaining Sprint 08 acceptance defects; shared-host escape/side-channel/host-wide DoS risks remain explicitly bounded by the academic scope.  
Handoff: the verified runtime suffix and owner walkthrough are in the operations guide. Arbitrary packages/integrations, inline guards, automatic advancement and per-ticket source edits remain outside scope.
