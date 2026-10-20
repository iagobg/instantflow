# Sprint 08 — Isolated Python calculations

[Sprint index](sprint_index.md) · Status: Proposed / gated · Dependencies: Sprint 07; D-16, D-17

Goal: prove one customer-specific calculation through a separately isolated, asynchronous runner. This is an optional extension after the four-process proof of concept, not a new condition for completing Sprints 00–07.

Specification: [Custom Python automation](../design/10-python-automation.md).

## Readiness gate

Resolve the concrete use case, isolated hosting feasibility, operating cost, data scope, patch/security owner, and recovery/kill-switch procedure before moving to Ready. No Python execution is authorized merely by reserving a future capability name. If the gate fails, keep built-in actions and leave this sprint gated.

## Tasks

- [ ] S08-T01 Validate use case and threat model; evaluate isolation/runtime hosting and record the go/no-go decision.
- [ ] S08-T02 Implement immutable script catalogue, separate review/activation permissions, schemas, synthetic fixtures, and versioned reference-only workflow bindings.
- [ ] S08-T03 Implement bounded isolated runner and dispatch protocol, deny network/credentials, enforce external resource limits and cleanup, add emergency disablement.
- [ ] S08-T04 Implement durable run intents, leases/fencing, independent workers, validated idempotent result application, waiting-stage freshness guards, PT-BR status/retry UX.
- [ ] S08-T05 Verify hostile workloads, confidentiality, races/recovery, import boundaries, measured limits, and documented operating procedures.

## Acceptance criteria

- An authorized reviewer activates a versioned calculation; a configured transition runs it on declared synthetic inputs and applies only allowed output fields.
- Customer Python never runs in Phoenix or inside a database transaction and receives no application credentials or arbitrary record access.
- Isolated workloads cannot reach prohibited network/host resources in the tested environment; resource exhaustion is contained and cleanup succeeds. Evidence states the limits of this testing.
- No script can directly send email, approve, spend, alter permissions, or change stages. Domain guards remain authoritative.
- Permission revocation, script disablement, cancellation, or changed input prevents stale/unauthorized result application.
- Duplicate dispatch, expired leases, retries, and late results cannot apply a logical result twice. Script failure cannot satisfy a required-result guard.
- A long calculation does not block refresh delivery or hold ticket locks; users see clear waiting/failure states.
- Workflow imports contain only symbolic references and cannot activate source or bypass local review.
- A documented owner can disable execution, reject pending results, patch runtime images, and inspect bounded authorized diagnostics.
- Two organizations cannot share script grants, bindings, snapshots, scratch space, results, or diagnostics implicitly. A busy tenant cannot exhaust the other's allocated execution capacity; suspension and wrong-tenant runner responses fail closed.

## Progress

Actual start / finish: — / —  
Evidence: design judgment only; no runtime implemented.  
Gate owner: product owner with implementation/security operator (to be assigned).  
Outstanding: D-17 and readiness gate.  
Handoff: limited calculation capability; arbitrary integrations/packages, inline guards, auto-advancement, and per-ticket source editing remain outside scope.
