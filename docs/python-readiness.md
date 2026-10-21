# Sprint 08 readiness assessment

Completed 2026-10-21. Target-host isolation, broker recovery and deployed-release integration passed; the private university deployment is explicitly enabled.

## Confirmed scope and decision

The user selected a synthetic field-trip cost calculator, retained uploaded Python scripts, and specified a private university deployment accessible only with credentials they hold. The host is Oracle Ampere A1 ARM / Ubuntu / 4 OCPUs / 24 GB RAM, shared with Phoenix and PostgreSQL.

The user explicitly chose: “Same VPS with gVisor; revise the host-separation requirement for the university demo.” This supersedes the original requirement for separate execution infrastructure. gVisor is the chosen implementation target on this VM. The trusted broker runs as a separate OS account/process; Phoenix has no Docker access. A successful sandbox escape could still reach the app/database host. This is a deliberately accepted academic limitation, with synthetic data only.

The operating default is that the project owner maintains and disables the private deployment using the supplied [operator procedure](python-calculations.md). No additional paid infrastructure is proposed or deployed. The user's actual tenancy billing and available host capacity are not independently verified.

## Calculation contract

The supplied example calculates vehicle count by ceiling participants/capacity, transport as vehicles × (base + kilometres × rate), admission as participants × admission price, and total as transport + admission. Inputs and outputs are bounded integers; money is in cents. The 81-person / 40-seat / 120-km fixture returns 3 vehicles and 402,000 cents.

Only declared synthetic values enter the workload. The returned quotation is a read-only section with no broader readership than its inputs. It cannot directly populate finance-effect fields or perform approvals, spending, record fetches, permission edits or stage changes. The workflow explicitly waits for and reviews an exact current result. Revised inputs require a new run through correction/recalculation.

## Hosting evaluation

[gVisor's FAQ](https://gvisor.dev/docs/user_guide/faq/) documents ARM64 support. Its [platform guide](https://gvisor.dev/docs/user_guide/platforms/) describes the default systrap platform for VMs without requiring nested KVM. These support evaluating it on the A1, but do not establish compatibility or containment on the user's actual VM.

[Firecracker](https://github.com/firecracker-microvm/firecracker/blob/main/docs/getting-started.md) requires usable KVM. That has not been demonstrated here; Firecracker is not the selected runtime.

The initial development PATH inventory did not find Docker/runsc. A subsequent inspection found Docker via /snap/bin/docker, with an amd64 daemon and only ordinary runc runtimes registered. This local environment is not the ARM target. The remote A1 now runs checksum-pinned gVisor `release-20261012.0`, installed using Docker reload while preserving all 13 existing containers. Target-host isolation, service recovery and deployed-release application acceptance pass. The live node uses the authenticated Unix socket and its durable enable switch is active.

## Readiness outcome

| Item | Outcome |
|---|---|
| Use case/data | Confirmed: synthetic trip calculation and private university scope. No real customer required. |
| Hosting/topology | Same Oracle A1 VM with gVisor, explicitly approved as a design revision. |
| Operating cost | Existing host; no additional subscription or purchase. Actual billing remains owner-controlled. |
| Ownership/procedure | Single-owner operating default; shutdown, patch and recovery runbook supplied. |
| Application control plane | Catalogue, permissions, fixtures/review, immutable bindings, durable runs, leases/fences, result guards, retries/cancellation and PT-BR UX implemented and locally tested. |
| Host verification | Passed on Ubuntu 22.04.5 / kernel 6.8.0-1062-oracle / aarch64: real runsc/image, resource denial, cleanup, emergency shutdown, orphan reconciliation and broker/worker recovery. |

Go for the explicitly approved synthetic academic deployment; Sprint 08 is Done. Defaults remain disabled for other deployments. Evidence: [isolation](evidence/sprint08-a1-isolation.json), [broker service/recovery](evidence/sprint08-a1-service.json), [application/lease recovery](evidence/sprint08-a1-application.json), and [live enablement](evidence/sprint08-a1-deployment.json). These targeted checks do not prove absence of escapes, side channels or all host-wide denial of service.

## Threat model and configured controls

Treat uploaded source, stdout, JSON output and responses as untrusted. Protect host/database credentials, organization-local snapshots/results, other organizations' execution capacity and domain authority. Source is immutable and separately permissioned; importing a workflow never activates code.

The broker requires a digest-pinned approved image, runsc, network denial, no host mounts or inherited secrets, read-only unprivileged workloads, fresh bounded scratch and external resource/output/time limits. Two global slots and one per organization are enforced by the broker as well as application scheduling. Cleanup failure refuses further broker work; an operator watchdog handles orphaned labelled containers. Durable generation checks reject results after global or script disablement. Actor revocation, organization suspension, stage/input edits, cancellation, wrong-tenant responses and obsolete fences fail closed.

The [operations guide](python-calculations.md) defines the actual limits, credentials/account separation, seven-day synthetic payload retention, image patching, runbook and real-host acceptance harness. Tests of controller logic or ordinary containers cannot substitute for those host measurements. Same-host escape/side-channel/host-wide denial-of-service risks remain; no proof of their absence is claimed.
