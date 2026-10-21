# Python calculations — private university demonstration

Sprint 08 targets the owner's Oracle Ampere A1 Ubuntu VM (4 OCPUs, 24 GB RAM), shared with Phoenix and PostgreSQL. On 2026-10-21 the owner explicitly approved gVisor on this same VM, revising the original separate-host requirement. Only synthetic data and privately gated application access are in scope.

A successful escape could reach the application/database host. This residual risk is accepted for this academic topology; it is not a claim of equivalent separation or suitability for real clients. Ordinary containers, a Python subprocess, AST restrictions or a venv are not accepted substitutes for gVisor. Execution remains disabled by default. The target VPS now has the reviewed gVisor runtime and an isolated broker; the target-host acceptance gates below have passed and the private university deployment is enabled.

## What is implemented

Organization-local immutable script versions pin source, integer input/output schemas, synthetic fixtures, allowed local profiles and the final Python image digest. Changing any of those creates a different content digest. Authors cannot activate scripts through publication. Separate grants cover authoring, review/activation, binding, execution and source access. In this single-owner demo the same person may receive each distinct grant; two-person review is not claimed.

A workflow transition carries a symbolic script key/content digest and declared field mappings. Publication requires a locally reviewed/active script and the binding grant. Imports create drafts and cannot install or activate source. The transition editor preserves calculation references; change their mappings through reviewed JSON import. Unsupported runtime images fail closed at the broker.

The transition commits a waiting stage and a durable intent. Dedicated workers claim expiring fenced leases, leave database transactions before HTTP dispatch, and validate current authority, organization status, script generation, exact stage/input revisions, response identity and allowed outputs before applying once. A relevant input edit or stage change invalidates results. Unchanged-input retries reuse the run, with at most three attempts. Revised inputs need a new run through the workflow's correction/recalculate path. A required-result guard blocks continuation when a result is missing, failed, expired or stale. No script can request arbitrary patches, approvals, spending, permissions or stage changes.

Computed sections are read-only. Output readership cannot exceed input readership, and outputs cannot target fields used by finance effects. The supplied trip workflow records a reviewed quotation, without reserving or spending funds. Calculation execution is separate from refresh delivery; statuses, generic failure guidance, retry and cancellation are in PT-BR.

Each organization has at most 20 outstanding runs and 100 immutable script versions; the catalogue shows the latest 100 versions. The worker rotates organizations, with one running attempt per organization and two in total per node. The broker independently limits concurrency to two, one per organization. Per-attempt limits are 1 CPU, 128 MiB RAM/swap cap, 64 host tasks plus a 32-process guest limit, 5-second wall time, 8 MiB scratch, 16 KiB stdout and 20 KiB combined stdout/stderr. The aggregate slice targets 2 CPUs, 512 MiB memory, no swap and 128 tasks. Real ARM64 tests found that a 16-task ceiling prevented gVisor startup; the current allowance includes runtime overhead.

Only declared integers enter workloads. No run/tenant identity, broker token, database credentials, attachments or record-fetching capability is passed into Python. Raw stdout/stderr is discarded; ticket diagnostics contain fixed messages. Terminal run snapshots, retained result JSON and diagnostics are cleared after seven days by the ordinary delivery poller, marking the run stale. Queue/running records await recovery; approved source/fixtures and data-free attempt metadata remain for reproducibility. Derived ticket fields remain under the ticket's own retention policy. Backups need a separate operator retention policy.

## VPS preparation — operator, not the web service

The operating default for this single-owner project is that the project owner maintains Ubuntu, Docker, gVisor and runtime images and performs emergency shutdown. No additional paid infrastructure is required by this topology; actual tenancy billing remains the owner's responsibility.

1. Install Docker and the official ARM64 gVisor runtime on the VM, using the [gVisor installation guide](https://gvisor.dev/docs/user_guide/install/) and [Docker integration](https://gvisor.dev/docs/user_guide/quick_start/docker/). Register the runtime as `runsc`, using its default `systrap` platform. Pin and record the installed version/checksum. Do not assume nested KVM availability. Validate Ubuntu/kernel and cgroup support locally.
2. Keep Phoenix's OS account out of the Docker group and away from the Docker socket, operator database credentials and broker configuration. Create a separate `instantflow-runner` OS account/group, with Docker access. Docker access is privileged host authority; the trusted broker must never accept arbitrary Docker flags, image names or host paths from application requests.
3. Copy the reviewed `runner/` directory to `/opt/instantflow/runner`, owned by root and not writable by either application account. Install `instantflow-python.slice`, the broker service, and the reaper service/timer from that directory under `/etc/systemd/system/`. Enable the reaper timer and reload systemd. Confirm the actual Docker daemon uses the systemd cgroup driver and honors that parent slice before relying on aggregate limits.
4. Build a reviewed Python image using an ARM64-compatible base pinned by digest. There are no runtime package downloads or arbitrary dependencies. For example, after setting `PYTHON_BASE` to an approved `python@sha256:...` reference:

~~~sh
docker build --build-arg PYTHON_BASE="$PYTHON_BASE" -t instantflow-python:reviewed runner/
docker image inspect instantflow-python:reviewed --format '{{.Id}}'
~~~

Use the returned immutable `sha256:...` image ID for `PYTHON_IMAGE`; a locally available registry manifest digest also works. Nothing automatically pulls an image at execution. Script registration uses its 64-character hex suffix as `runtime`. A rebuilt/patched image needs new script versions and review.

5. Create root-owned `/etc/instantflow-python/`. Store a newly generated token of at least 32 random bytes and the pinned image in `broker.env`, readable only by root and the runner service group. Required settings are `PYTHON_BROKER_TOKEN` and `PYTHON_IMAGE`. For container deployments, use `PYTHON_BROKER_SOCKET=/run/instantflow-python/broker.sock` and `PYTHON_BROKER_SOCKET_GID=65534`. The broker creates a 0660 Unix socket, with a stable runtime directory across restarts. Bind only that directory read-only into Phoenix using the opt-in Compose fragment. Do not expose broker TCP or mount Docker into Phoenix. Local development may use loopback instead.
6. Create the root-owned `/etc/instantflow-python/ENABLED` marker for the isolated synthetic rehearsal. Start the broker. It refuses startup without `runsc` and never falls back to `runc`. No application execution is enabled by this marker alone.
7. Run the host acceptance harness with the reviewed image and save its JSON evidence:

~~~sh
PYTHON_IMAGE="$PYTHON_IMAGE" python3 runner/verify.py > a1-python-isolation.json
~~~

Run it with the operator's Docker authority on a synthetic deployment. It performs real resource-exhaustion attempts, network/host-resource denial probes, fresh-scratch checks across two synthetic organizations, post-failure recovery and leftover-container checks. Run it without concurrent legitimate calculation jobs, because its final cleanup check expects no labelled containers. It does not prove absence of escapes or all side channels. Exercise the emergency marker removal during an active workload and measure the external watchdog separately.

Run `runner/verify_service.py` with the same operator environment to exercise authenticated Unix transport, per-tenant/global admission, healthy progress beside a CPU loop, emergency removal, forced broker death, watchdog cleanup and socket-directory stability. These checks require no legitimate calculations in flight.

8. Apply both forward migrations using OperatorRepo. Give only the serving process `PYTHON_EXECUTION=true`, `PYTHON_BROKER_URL=http://127.0.0.1:4010` and `PYTHON_BROKER_TOKEN`. Never give Phoenix the operator database URL, image-building privilege or Docker access. The operator then uses:

~~~sh
mix instantflow.python enable
~~~

For a production checkout, use `MIX_ENV=prod` and the operator-only database configuration. The serving release need not include Mix: in an operator-only one-off container, use `bin/instantflow eval 'Instantflow.Release.python_switch(true)'` (or `false` to disable). The serving process must never receive the operator URL. Each switch change increments a durable generation and appends an operator-role audit row. The web runtime can read/lock the switch but cannot change it. Activation is contingent on the A1 acceptance evidence; the task does not certify isolation.

## Repeatable host tooling

After reviewing the source, run `runner/install_host.py --source /absolute/reviewed/runner`
as root on ARM64 Ubuntu. It verifies the pinned official archive checksum, keeps
the adjacent gVisor sidecars, preserves Docker daemon options, uses reload and
checks existing container start times. It installs the broker/watchdog without
enabling application execution. `runner/prepare_image.py /absolute/reviewed/runner`
resolves an official Python base digest, builds the trusted entrypoint image,
pins its image ID in the private broker environment and prints public identities.

Run `runner/rehearse_host.py STACK_ROOT /absolute/reviewed/runner/rehearse.exs`
as operator after the app image is deployed. It creates a randomly named database,
migrates it without changing the shared runtime password, starts the actual release
against it with web serving disabled, and removes the container/database afterward.
The rehearsal exercises real fixtures, two organizations, worker death, real lease
expiry, late replies, read-only output and durable generation fencing. Failure
diagnostics are root-only; delete them after investigation.

Save successful `isolation.json`, `service.json` and `application.json` in a
private evidence directory. `runner/enable_host.py STACK_ROOT REVIEWED_COMPOSE_FRAGMENT
EVIDENCE_DIRECTORY` requires fresh passing reports matching the current release
and runtime image. It installs the opt-in fragment and private token file,
recreates only Instantflow, checks credential/Docker separation and enables the
durable switch. It fences the switch on failure. Normal image pushes preserve
this opt-in. Broker/runtime host-file changes require operator application and
fresh host acceptance; they are not automatically installed by an app image push.

The accepted guest runtime suffix for this deployment is
`4b4b8f21f94fd36e53af1ab108ee0871f64594139a4270ae25c11d0313100961`.
Use it when registering the example. Rebuilding the image requires a new suffix
and new reviewed script/workflow versions.

## Demonstration walkthrough

In **Equipe e convites**, explicitly grant the owner `python_author`, `python_reviewer`, `python_binder`, `python_execute` and `python_source`. Administration alone grants none of these. A requester also needs its ordinary local workflow profile and current input/output section access.

Open **Cálculos Python**. Use **Carregar exemplo de passeio** or upload `priv/calculations/field_trip.py`. Supply the approved runtime digest, review the schemas/fixtures, and register the immutable version. **Revisar código** requires source access. **Verificar exemplos** runs the synthetic fixtures asynchronously outside database transactions. Only then can an authorized reviewer explicitly activate the version.

For the supplied example, **Gerar fluxo do exemplo de passeio** produces reference-only JSON. Import it through **Modelos de fluxo** and map the requester role to the intended local profile (e.g. `admin` for the sole owner), the reviewer role to the intended local profile and the responsible department to a local department. Publish with the binding grant. The generated workflow is specific to the supplied example's schemas; publication rejects incompatible scripts.

Create a request and enter 81 participants, capacity 40, 120 round-trip km, base 50,000 cents, rate 250 cents/km and admission 2,000 cents/person. **Calcular cotação** enters the waiting stage. Expected output: 3 vehicles, transport 240,000 cents, admission 162,000 cents and total 402,000 cents. Review and explicitly confirm the quotation. **Revisar entradas** returns to preparation and invalidates the prior run; calculate again after editing. Failure cannot satisfy the continuation guard.

## Shutdown, recovery and patching

1. Run `mix instantflow.python disable` with operator credentials first. Its durable switch blocks dispatch/finalization and invalidates old generations even after re-enabling. Remove the broker's `ENABLED` marker. Active brokers check it while polling workloads and remove their complete containers.
2. Verify that no containers labelled `instantflow.python=true` remain. The reaper removes only labelled workloads older than 15 seconds on a 10-second timer. It is a backup for broker death/late daemon creation, not a replacement for synchronous cleanup. Never remove unrelated containers. Check the daemon if removal fails. A cleanup failure latches that broker into refusal until the operator reconciles containers and restarts it. Startup removes existing labelled orphans before opening the socket; failed reconciliation refuses startup, so restarting cannot silently reset admission counters over surviving work.
3. Inspect only authorized run status and immutable attempt metadata. Source and fixtures require their separate access grant. Do not turn raw source/inputs/stdout into application or reverse-proxy logs.
4. Patch Ubuntu/gVisor and build a new digest-pinned Python image. Repeat host containment, kill/restart and application recovery checks. Update the broker image configuration, create/review new script versions and publish explicit new workflow versions; existing tickets never resolve a mutable latest script.
5. Re-enable only after reconciliation. Expired leases use new fences; old replies cannot finalize. Old switch/script generations become stale, requiring the workflow's correction/recalculate path. A broker transport failure can be retried for unchanged inputs at most three times. Cancellation stops application of results immediately; workload removal occurs on completion/timeout or emergency shutdown.

## Evidence and remaining release gate

Application tests use a deterministic protocol adapter, real loopback HTTP tests and independent non-owner database connections for concurrent claiming/finalization. Python controller tests use trusted subprocess stubs; the repository example is tested as trusted source. These are not evidence that uploaded hostile code was contained.

The local Docker daemon is not the ARM target. Real target-host checks passed on Ubuntu 22.04.5, kernel 6.8.0-1062-oracle, aarch64, with gVisor `release-20261012.0`. See the [isolation evidence](evidence/sprint08-a1-isolation.json), [service/recovery evidence](evidence/sprint08-a1-service.json), [deployed-release rehearsal](evidence/sprint08-a1-application.json) and [enablement record](evidence/sprint08-a1-deployment.json). The separate synthetic database was removed after the rehearsal. Both organizations produced 402,000 cents; another tenant progressed in 617 ms after a worker died, and the abandoned lease recovered in 20,733 ms with a new fence. Targeted checks retain the shared-host limitations in the [readiness assessment](python-readiness.md). Sprint 08 is Done for this scope.
