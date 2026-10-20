# Custom Python automation

[Design index](index.md) · Decision: D-16 · Updated: 2026-10-20

## Judgment

Worth designing for now; not worth adding arbitrary execution to the current proof of concept. Complex customer calculations fit the platform's customization goal, and Sprint 01 already provides immutable workflow versions, action validation, transactional outbox intents, and idempotent commands. No foundational rewrite is required. Operating a hostile-code runner, however, is a substantial additional security and reliability responsibility.

Keep Sprints 02–07 focused on permissions, editor, and four school slices. Add a gated Sprint 08 for one concrete calculation that is awkward in the bounded rule language. Python is one useful authoring language, not a security boundary. Never promise that malicious code cannot escape: isolation reduces risk and requires patching, testing, monitoring, and incident ownership.

## Suitable first use

Example: a customer-specific trip cost calculation using participant count, distance, and approved rate inputs. Return a typed cost breakdown for staff review. The computation cannot reserve money, approve the trip, or mark payment received. Keep ordinary comparisons and stage guards in the built-in engine; email remains a registered application action.

Scope: an administrator registers/reviews an immutable script version, binds selected inputs and output fields to a workflow transition, and runs it for eligible tickets. Ordinary ticket submitters cannot attach arbitrary code. Selection may use existing declarative conditions. Per-ticket one-off source edits, package installation, arbitrary network calls, uploaded executables, and general integrations are deferred.

Administrators, scripts, bindings, run intents, snapshots, outputs, and review grants are organization-local. A user with memberships in A and B cannot bind A's script or fields to B's workflow. Carry validated organization identity through dispatch, lease/fencing, response verification, and finalization; no inherited/default worker scope. Organization suspension invalidates execution/application. Enforce per-organization quotas and fair scheduling, fresh sandbox state, and no cross-organization scratch/cache reuse. Global operator controls cannot expose script inputs or results to other tenants.

## Execution contract

- Script versions pin source digest, Python/runtime image version, fixed dependencies, input/output schemas, permissions, and resource limits. Updating source creates a new version; published workflows and queued runs never resolve a mutable “latest”.
- A run receives bounded JSON with only declared, authorized fields plus explicit calculation inputs. No database/session objects, credentials, raw attachments, counselor notes by default, environment secrets, or ability to fetch other records.
- Input access must satisfy both the initiating actor's current access and the approved automation grant. A broader service identity would be a separate product/security decision, not an implicit administrator override.
- A script returns bounded JSON with declared computed values. No generic patches, target record IDs, SQL, transition instructions, roles, payments, or arbitrary effect requests are accepted.
- Output is untrusted. Validate schema, size, finite numeric values, ranges, field allowlist, stage, revisions, and current authority before applying through ordinary domain commands.
- Derived values/logs inherit at least the confidentiality of their inputs. Mapping sensitive input into a public output requires explicit policy review; schema validation alone cannot prevent disclosure.
- Initial scripts have no I/O capabilities. Do not claim arbitrary Python is deterministic; pin inputs/runtime and record accepted outputs. Retries may execute more than once, while result application is deduplicated.

## Timing, concurrency, and failure

1. A permitted transition commits into a configured waiting stage and records a unique run intent with event ID, action key, pinned script version, selected input snapshot and revision vector. Never execute Python during the transition transaction.
2. A dispatcher claims a run in a short transaction with lease and fencing token. It dispatches to an isolated runner outside database locks. Expired leases permit recovery; old workers cannot finalize after a newer claim.
3. A short finalization transaction validates the claim, run identity, output, current permissions, expected ticket stage, relevant revisions, and script enablement. Apply allowed values and audit exactly once per logical run.
4. A user can perform the next transition only when the required successful result matches the current input revision vector and exact script/action version. A past success of the same action type is insufficient.

The current `Delivery.complete/1` performs deterministic simulation within a transaction; it must not wrap a Python call. The current worker drains deliveries serially; Python needs bounded independent execution so slow scripts cannot delay refresh events. Existing delivery guards aggregate success by kind; Python results need per-run/action/revision identity instead of reusing that coarse check.

Timeout, invalid output, unavailable runner, or failure leaves the ticket waiting with PT-BR status and retry guidance. No automatic rollback of an already committed transition, no fail-open approval, and no unlimited retries. Cancellation or input edits invalidate pending results; late output is discarded. Retry of unchanged input reuses the logical run; changed input requires a new run. Required automation cannot be bypassed by a generic retry or administrator action.

Keep a separate run status: queued, running, succeeded, failed, timed out, cancelled, stale. User-facing equivalents include “Na fila”, “Em execução”, “Falhou”, and “Resultado desatualizado”. Display bounded, authorized diagnostics without exposing source or sensitive inputs to unrelated viewers. This scope does not automatically advance tickets or recursively trigger other scripts.

## Isolation requirements

Evaluate a hardened sandbox runtime such as gVisor or microVM isolation such as Firecracker against the actual deployment. Select during the Sprint 08 gate, not by assumption about local WSL or a cheap VPS. Prefer an established isolation system or evaluated managed service over a homemade Python sandbox.

- Separate execution infrastructure from Phoenix, PostgreSQL, storage credentials, and control-plane privileges. A hypothetical guest escape should not place the attacker on the application's privileged host.
- Fresh isolated environment for each attempt; fixed read-only runtime, bounded scratch storage, unprivileged execution, no host mounts, Docker socket, shared writable caches, or inherited secrets.
- Deny network at infrastructure level, including DNS, metadata endpoints, internal services, and IPv6 paths. The Python process receives no runner/control-plane credentials.
- Enforce CPU, wall-clock, memory, process/thread, disk, output, and log limits outside Python; terminate the full workload, not just a cooperative function. Bound queue depth/concurrency and per-organization run quotas.
- No runtime package downloads. Curated dependencies are separately reviewed and image-pinned. Patches require tested image versions and emergency disablement of vulnerable versions.
- Authenticate runner communication; bind responses to run identity/attempt. Grant the dispatcher only the ability to submit/collect constrained jobs, never broad infrastructure administration.
- Maintain a kill switch that blocks new runs and rejects late results, bounded retries, cleanup, audit trails, and retention rules for inputs/results/logs. Stdout is untrusted potentially sensitive content, not ordinary application telemetry.

AST checks/import allowlists can improve usability but are not containment. RestrictedPython explicitly says it is not a sandbox. A subprocess, venv, stripped builtins, or ordinary container alone is not the proposed security boundary. Isolation testing does not prove absence of escapes.

## Authoring and interchange

Separate permissions for script authoring, review/activation, workflow binding, execution, source access, and output access. Publishing a workflow alone cannot activate code. Require authorized review and synthetic test fixtures before activation; when staffing permits, use a different reviewer from the author.

Workflow import/export initially carries only symbolic references to reviewed script versions and declared mappings, never inline source or automatically installed code. Local binding must resolve exact reviewed versions. Unsupported runtimes/capabilities fail closed. Keep the LLM workflow guide declarative; any later script-authoring guide is a separate artifact with a separate approval path.

## Gate and evidence

Before implementation, establish a real calculation use case, hosting compatibility, acceptable runtime/cost, data classification, security/patching owner, and recovery/disablement procedure. If these are not established, keep the feature disabled and continue shipping built-in actions.

Acceptance tests cover allowed calculation; blocked network/files/credentials; CPU/memory/process/output exhaustion; cleanup and cross-run leakage; forged output; sensitive-output mappings; stale input; role revocation; disabled script; duplicate dispatch; worker death/lease recovery; late results; cancellation; and unauthorized imports. Use synthetic data. Separately test concurrency through independent database connections. Record measured limits and residual risks before enabling customer scripts.

## Primary references

- [RestrictedPython documentation](https://restrictedpython.readthedocs.io/en/stable/index.html): explicitly not a sandbox or secured environment.
- [gVisor security architecture](https://gvisor.dev/docs/architecture_guide/intro/): isolation beyond direct application access to the host kernel.
- [gVisor production guide](https://gvisor.dev/docs/user_guide/production/): deployment tradeoffs for untrusted workloads.
- [Firecracker design](https://github.com/firecracker-microvm/firecracker/blob/main/docs/design.md): microVM architecture and isolation model.

The proposed application contract and sequencing are project judgments, not guarantees supplied by these technologies.
