# Deployment reference for LLM reviews

This document describes Instantflow's deployment architecture, the files that control it, and the evidence available to a future reviewer. It is a reference for understanding and assessing the setup, rather than a first-time installation walkthrough.

## Scope and sources of truth

Instantflow follows the other projects in the WSL workspace: GitHub Actions publishes an ARM64 image to GHCR, then redeploys one application through the VPS's shared Docker Compose/Caddy stack.

| Concern | Source |
| --- | --- |
| CI gates and deployment triggers | [checks.yml](../.github/workflows/checks.yml) |
| Image publication and SSH orchestration | [deploy.yml](../.github/workflows/deploy.yml) |
| Release build and Docker build-context exclusions | [Dockerfile](../Dockerfile), [.dockerignore](../.dockerignore) |
| Backup, migration, restart, and image recording | [redeploy.sh](redeploy.sh) |
| Application/database service definitions | [instantflow.compose.yml](oracle-caddy/projects/instantflow.compose.yml) |
| HTTPS routing | [instantflow.caddy](oracle-caddy/caddy-sites/instantflow.caddy) |
| Operator-only release migrations | [Instantflow.Release](../lib/instantflow/release.ex) |
| Runtime database identity check | [Instantflow.RuntimeDatabase](../lib/instantflow/runtime_database.ex) |
| Private configuration preparation | [install.py](install.py) and the adjacent `.env.example` templates |
| Application operating boundaries and account bootstrap | [deployment.md](../docs/deployment.md), [organizations-operations.md](../docs/organizations-operations.md) |

There are three distinct configuration locations:

- This repository contains reviewable templates and deployment code.
- `/home/iago/workspace/deploy/oracle-caddy/` contains the private local deployment configuration.
- `/home/ubuntu/apps/oracle-caddy/` contains the configuration actually used by the VPS.

A project push updates the application image. It does **not** synchronize Compose fragments, Caddy routes, or private environment files. Those files can drift between the repository, private local directory, and VPS; reviews need to distinguish intended configuration from observed deployed state. Shared `compose.yml`, `Caddyfile`, and other projects belong to the private deployment stack.

## Topology and configuration boundaries

The SSH alias is `portfolio-server`; the deployment target is `ubuntu@134.65.245.186`. The public endpoint is [instantflow.iagobussoletti.com.br](https://instantflow.iagobussoletti.com.br/entrar), with Cloudflare in front of the shared Caddy service.

| Service | Purpose and boundary |
| --- | --- |
| `instantflow` | Phoenix release, port 4000 on the shared web network and private database network; no host port published |
| `instantflow-db` | PostgreSQL 16.15, persistent `instantflow-data` volume, internal database network, no host port published |
| `instantflow-migrate` | Disposable service in the `tools` profile; operator credentials and private database network only |
| Shared `caddy` | Public HTTP/HTTPS entry point; route files imported from `caddy-sites/*.caddy` |

The web image runs as `nobody:nogroup`, drops capabilities, enables no-new-privileges, and has no Docker socket mount. Its database login is `instantflow_runtime`; application startup rejects an owner/superuser/BYPASSRLS/CREATEROLE identity. The migration process uses OperatorRepo without starting the web application. PostgreSQL's initialization/operator account is privileged because the existing migrations create roles and security-definer functions.

The private files beside the VPS's shared Compose file have separate consumers:

| File | Consumer and contents |
| --- | --- |
| `instantflow.env` | Web process: runtime database URL, Phoenix secret, host, and pool settings |
| `instantflow.operator.env` | Migration process: operator URL, runtime role password, and configuration required by release evaluation |
| `instantflow.db.env` | PostgreSQL initialization: database name and operator credentials |
| `instantflow.image.env` | Last image whose deployment completed the health wait; no credentials |

The three credential files have mode `600`. The runtime password must agree across both runtime URLs and `RUNTIME_DB_PASSWORD`; the operator password must agree between the database and migration files. PostgreSQL initialization variables only initialize an empty volume; editing an environment file alone does not rotate an existing login.

`install.py` prepares the private local directory, generates matching random credentials, preserves existing credentials, and refuses partial credential sets or conflicting project files. It does not start services or synchronize the VPS. Reviews can check configuration names, permissions, and consistency without printing secret values.

## GitHub Actions contract

A push to `main`, or a manual run of **Checks** on `main`, runs the foundation job before calling the reusable deployment workflow. Pull requests and other branches do not deploy. The foundation job includes project checks, Python tests, deployment tests, asset builds, rehearsals, and the benchmark.

The repository uses **repository Actions secrets**. There is no GitHub Environment or environment approval gate. The concurrency group named `instantflow-production` is only a serialization identifier.

| Secret | Role |
| --- | --- |
| `DEPLOY_HOST` | VPS address: `134.65.245.186` |
| `DEPLOY_USER` | SSH user: `ubuntu` |
| `DEPLOY_PATH` | Shared deployment root: `/home/ubuntu/apps/oracle-caddy` |
| `DEPLOY_SSH_KEY` | Dedicated Actions private key; its public key is authorized on the VPS |
| `DEPLOY_KNOWN_HOSTS` | Verified VPS host-key entry for strict SSH identity checking |

Application/database secrets stay in the private deployment files, outside Actions. `GITHUB_TOKEN` publishes images with package-write permission. The VPS successfully pulled the published image during initial verification; private registry access, if introduced later, would need authentication for the root Docker client used by `sudo`.

The publish job runs on `ubuntu-24.04-arm` and builds `linux/arm64`. Images are tagged `ghcr.io/iagobg/instantflow:<full-commit-sha>`; deployment does not use `latest`. SHA tags identify the selected revision, but the script does not pin a manifest digest.

Actions deployments are serialized without canceling a running deployment. The SSH job checks the current main-branch tip before proceeding and skips superseded commits. A separate host `flock` serializes script invocations, including manual ones.

## Deployment behavior and failure semantics

The checked-out Actions revision streams `redeploy.sh` to `bash -s` over SSH. No application source checkout is required on the VPS.

1. Validate the full-SHA GHCR image argument, acquire the host lock, and check required configuration files.
2. Pull the application/migration image and PostgreSQL image before stopping the web service.
3. Ensure the database is healthy.
4. Write a private custom-format `pg_dump` under `backups/instantflow/` and require a nonempty result.
5. Stop only the Instantflow web service for the migration window.
6. Run `Instantflow.Release.migrate()` in a disposable operator container, including runtime-role password configuration.
7. Start the web service with `--no-deps` and wait for its local login HTTP health check.
8. Atomically replace `instantflow.image.env` after the health wait succeeds, leaving the shared `.env` untouched.

CI/publication failures do not invoke the VPS script. Pull and backup failures occur before the script stops the web service. A migration failure leaves it stopped for intervention. A health failure fails the deployment but can leave the new container running or unhealthy; the image record still describes the previous successful deployment. That record alone is therefore not proof of the currently running image.

Migrations are forward-only and involve maintenance downtime. There is no automatic image rollback, schema downgrade, or database restore. Deploying an older image requires schema compatibility assessment; the script still runs pending migrations.

Routine image redeploys do not reload Caddy. Route changes require separate Caddy validation/reload. The initial certificate was issued by Let's Encrypt through the existing Cloudflare/Caddy path.

## Review-sensitive implementation details

These behaviors were established during the first VPS deployment and are covered where applicable by [test_redeploy.py](test_redeploy.py):

- `sudo` resets the caller's environment. The selected image is passed through `sudo env INSTANTFLOW_IMAGE=...`; exporting it only in the SSH shell fails Compose interpolation.
- Docker commands receive `/dev/null` as stdin. Otherwise, an interactive Docker command can consume the remainder of the script streamed over SSH and cause an incomplete deployment to appear successful.
- The shared `backups/` directory is root-owned on this VPS. Its `instantflow/` subdirectory is owned by `ubuntu:ubuntu` with mode `700`, allowing private snapshots without changing other projects' backup permissions.
- Commands use the shared root Compose file plus Instantflow's fragment and target specific services. Other project containers appear as Compose “orphans” in this partial view; removing them is not part of deployment.
- Private environment files are excluded from Git, and the Docker context allowlist excludes workspace credentials/data. Compose templates alone do not prove the live web container lacks operator credentials or Docker access.
- A clean CI database exposed an organization-ID collision in an enrollment fixture. The correction is in [enrollment_fixtures.ex](../test/support/enrollment_fixtures.ex); validation included the failing seed and a fresh temporary PostgreSQL cluster.

## Verification evidence and review entry points

On **2026-10-21**, [Actions run 39619134537](https://github.com/iagobg/instantflow/actions/runs/39619134537) completed successfully for commit `acd0b1afb3bd675be71a60345db32a6a564e2c5c`: foundation checks, ARM64 image publication, and automatic SSH redeployment all passed.

Post-deployment observations included:

- The VPS ran that exact image and both Instantflow containers were healthy.
- Public HTTPS login, compiled JavaScript, and compiled CSS returned HTTP 200; the unauthenticated root redirected to the login page.
- The automatic pre-deploy backup existed with mode `600` and a size of 200,175 bytes.
- The web container ran as `nobody:nogroup` without bind mounts, and PostgreSQL had no published port on its internal network.
- Existing VPS applications remained running with unchanged container uptimes.

This is historical evidence, not a statement that a future checkout or live deployment is unchanged. Current reviews can compare the running image, recorded image, workflow revision, template copies, health state, and backup metadata.

Local validation entry points are `mix precommit`, `python3 -m unittest discover -s deploy -p 'test_*.py' -v`, `python3 -m unittest discover -s runner -p 'test_*.py' -v`, and `bash -n deploy/redeploy.sh`. An x86 local release build does not establish ARM64 compatibility.

Read-only VPS checks, from `/home/ubuntu/apps/oracle-caddy/`, include:

```sh
sudo docker compose --env-file .env --env-file instantflow.image.env \
  -f compose.yml -f projects/instantflow.compose.yml --profile tools config --quiet
sudo docker compose --env-file .env --env-file instantflow.image.env \
  -f compose.yml -f projects/instantflow.compose.yml ps
sudo docker inspect oracle-caddy-instantflow-1 \
  --format 'image={{.Config.Image}} user={{.Config.User}} health={{.State.Health.Status}}'
curl --fail --silent --show-error --output /dev/null \
  --write-out '%{http_code}\n' https://instantflow.iagobussoletti.com.br/entrar
```

`config --quiet` validates without printing resolved credentials. Full resolved Compose output, container environment dumps, and unrestricted application logs can disclose private values.

## Remaining operating boundaries

Backups are local pre-deploy snapshots without automatic retention or off-host replication. A successful dump is not a restore rehearsal or a recovery-time guarantee. Recovery after incompatible migrations remains a planned restore/cutover operation.

The initial database contained no user accounts or demonstration seeds. Administrator/organization bootstrap is separate from deployment; production demo seeds are intentionally refused by the application.

Python execution is explicitly disabled in Compose. The deployment's success does not establish gVisor containment, uploaded-code execution readiness, or capacity for real workloads. Those boundaries remain documented in [python-readiness.md](../docs/python-readiness.md) and [python-calculations.md](../docs/python-calculations.md).

## Dedicated benchmark preservation

[benchmark_host.py](benchmark_host.py) implements preservation for the [database efficiency campaign](../docs/db-efficiency-plan.md). It runs as `ubuntu` from its installed location at `/home/ubuntu/apps/instantflow-benchmark/benchmark_host.py`, using Python 3.10+ and noninteractive sudo access to the local Docker socket. The frozen fixture remains tied to the historical image; schema-2 snapshots separately record the running application's immutable manifest. Historical schema-1 snapshots remain readable. Rollout commands are in [benchmark_rollout.py](benchmark_rollout.py).

The controller checks the fixed path/project/database, frozen fixture hash, exact Compose topology, private file ownership/modes, separate runtime credentials, actual container labels, image digest/revision/architecture, resource limits, loopback port, internal network, private volume and restricted runtime role. It refuses a database container containing unrelated databases. Unexpected configuration is an error requiring review; there is no target/path override or guard-bypass option.

After copying the reviewed controller to that exact location with mode `0600`, use:

```sh
ssh portfolio-server 'python3 /home/ubuntu/apps/instantflow-benchmark/benchmark_host.py inspect'
ssh portfolio-server 'python3 /home/ubuntu/apps/instantflow-benchmark/benchmark_host.py snapshot'
ssh portfolio-server 'python3 /home/ubuntu/apps/instantflow-benchmark/benchmark_host.py verify-snapshot --snapshot SNAPSHOT_ID'
```

`snapshot` writes a new private directory under `snapshots/`, containing `database.dump`, the five configuration files and a checksum manifest. PostgreSQL's [custom-format dump uses a consistent transaction snapshot while the application stays online](https://www.postgresql.org/docs/16/app-pgdump.html). The controller restores that dump into a randomly named `instantflow_benchmark_verify_*` database, inventories every public table and migration, checks that the runtime role sees zero tickets without tenant context, and drops only the database it successfully created. Inventory counts therefore describe the restored archive rather than a later observation of the live database. No record values or SQL parameters enter the report.

The completion manifest is written only after restore verification, temporary-database cleanup and a second configuration/identity check succeed. Dump, restore, RLS, cleanup or configuration-drift failures leave an incomplete private directory without a completion manifest. A failed CREATE does not authorize dropping an existing database. `verify-snapshot` checks identity and checksums, then repeats the restore and inventory comparison. If a killed process leaves a verification database behind, the next target guard refuses to proceed; investigate that explicitly before removing it.

Snapshots contain database contents and credentials. Keep directories at `0700`, files at `0600`, and workstation copies under ignored `.local/benchmark-preservation/`. Copy the complete snapshot and verify every manifest checksum before treating the off-host copy as usable. Only sanitized summaries belong in Git. This is a same-cluster restore rehearsal and private off-host copy, not a complete host-loss recovery rehearsal; PostgreSQL globals and the shared Caddy stack are outside this archive.

All controller operations hold `.benchmark-control.lock`. The campaign runner below retains it throughout preparation, workload and restoration. The installed `remote.py` compatibility wrapper refuses the historical runner's reset, host-change and sampling entry points; its status command uses the same lock. Keep the original script privately when installing the wrapper.

On 2026-11-06, the hosted target passed its guard, the snapshot passed two restore checks, and the private workstation copy matched all archive/configuration checksums. The archive contains 41 public tables and the current 15 tickets, rather than the frozen fixture's 12. Live table counts, application identity and all running container IDs/start times remained unchanged. See [sanitized preservation evidence](../docs/evidence/db-efficiency-benchmark-preservation-2026-11-06.json). Tests cover wrong targets, configuration drift, private permissions, unexpected runtime privileges, partial/tampered snapshots, restore/cleanup failures and concurrent controller invocations.

## Guarded benchmark rollout and restoration

Install `benchmark_host.py`, `benchmark_candidate.py`, `benchmark_rollout.py` and `benchmark_smoke.py` together in the private benchmark directory, with mode `0600`, while holding `.benchmark-control.lock`. Keep the previous controller files privately until validation succeeds. Put an existing synthetic fixture actor's `email`, `password` and `/o/SLUG/processos/ID/registros/ID` path in `smoke-private.json` (`0600`); no credentials belong in command arguments or Git.

The publication workflow now emits a schema-2 candidate artifact with the exact successful Checks run, publication run and publication attempt. Obtain the manifest from that trusted Actions artifact and copy it privately to the benchmark host. Deployment verifies both runs through GitHub, pulls only the immutable digest, and verifies ARM64, image revision and repository labels. This is operator-controlled artifact provenance, not a cryptographic build attestation; arbitrary operator-written manifests are not an independent supply-chain trust source. Initial candidate selection fails closed when GitHub is unavailable. Recovery and restoration use already retained, verified image bytes and do not require GitHub or a registry.

Publication can be requested with a lightweight tag named `benchmark-candidate-FULL_COMMIT-SUCCESSFUL_CHECKS_RUN_ID` pointing at that exact commit. Push the candidate branch first, wait for its successful Checks run, then push only that explicit tag. The workflow rejects a mismatched tag/commit/run before building. This [tag push trigger](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#push) works from the candidate revision without first merging the workflow into the serving branch; manual dispatch remains available once the workflow is on the default branch. Checks run on branch pushes, pull requests and manual dispatch; publication tags reuse the explicitly selected passing run. Publication creates an ARM64 digest/manifest and performs no deployment.

```sh
ssh portfolio-server 'python3 /home/ubuntu/apps/instantflow-benchmark/benchmark_rollout.py smoke'
ssh portfolio-server 'python3 /home/ubuntu/apps/instantflow-benchmark/benchmark_rollout.py deploy --candidate /home/ubuntu/apps/instantflow-benchmark/candidate.json'
ssh portfolio-server 'python3 /home/ubuntu/apps/instantflow-benchmark/benchmark_rollout.py restore --snapshot SNAPSHOT_ID'
ssh portfolio-server 'python3 /home/ubuntu/apps/instantflow-benchmark/benchmark_rollout.py recover'
```

`deploy` preserves the current records and applies the candidate's migrations. For a controlled benchmark fixture reset, add `--fixture`; the historical arm is `deploy --baseline --fixture`. Both arms restore the identical frozen archive, and the candidate applies its migrations afterward. Every operation first checks the current target and authenticated access, records a durable journal, stops only benchmark web, takes a fresh verified recovery snapshot, and only then changes the database. A candidate-to-different-image change requires a matching snapshot or explicit frozen fixture reset; starting older code on a newer schema is refused.

Migrations run in a uniquely named temporary container on only the internal benchmark database network, with the application CPU/memory limits, `nobody:nogroup`, dropped capabilities and no published port, volume or Docker socket. Only that container receives the operator URL and runtime password. Its exit status is checked and the container/private environment file removed, including after a timeout. The permanent web environment continues to contain only restricted runtime credentials.

Restoration checks the snapshot's image, configuration, checksums and restored inventory before stopping web. It recreates only `instantflow_benchmark` in the already guarded exclusive cluster, restores the archive transactionally, verifies all table counts/migration versions and fail-closed runtime RLS, and starts the snapshot's matching image. [PostgreSQL database deletion is not transactional](https://www.postgresql.org/docs/16/sql-dropdatabase.html); the durable journal and independently verified recovery archive cover this boundary. A failed migration, start or authenticated smoke restores the freshly preserved database and image together. If recovery itself fails, the journal remains and ordinary operations refuse to continue. `recover` handles a missing benchmark database or web container after an interrupted recreation. It refuses unrelated databases, changed credentials/topology, tampered archives and substituted recovery manifests. Do not remove the journal to bypass a failure, prune retained image bytes, or run legacy reset commands during recovery.

Success requires a healthy container plus login, authorized record read, logout and proof the logged-out session cannot read the record. The smoke uses local Caddy's TLS socket while validating the public hostname and certificate; it does not export cookies, HTML, account values or record contents. This verifies HTTP access; browser/WebSocket behavior belongs to the runner campaign. Snapshots contain secrets and preserve complete database state, whereas the reported table inventory is an aggregate comparison rather than a row-by-row semantic comparison.

The [restoration rehearsal](../docs/evidence/db-efficiency-benchmark-restoration-2026-11-06.json) restored a fresh off-host-verified 15-record/41-table snapshot on the dedicated host and passed the authenticated checks. The database container and all other running containers retained their IDs; only benchmark web was stopped and restarted. Candidate migration failure/recovery paths are covered by fault-injection tests. A real candidate migration remains pending publication: on 2026-11-06 the default branch still had only the historical release and no candidate workflow.

## Campaign runner and provenance

Install `benchmark_session.py` and `benchmark_provenance.py` beside the rollout modules, and install `benchmark_legacy.py` as `remote.py`, all at `0600` under the host lock. The workstation entry point is [benchmark_run.py](benchmark_run.py). It accepts an explicit historical arm or a trusted candidate artifact; it never derives the application revision from the frozen fixture manifest. The existing school workload/fixture remain external inputs and are not regenerated or edited. Only the reviewed workload hash is accepted; adding another workload requires a reviewed hash/contract update.

```sh
python3 deploy/benchmark_run.py --baseline \
  --workload benchmarks/k6/school.js \
  --fixture .local/school-benchmark/manifest.json \
  --output .local/benchmark-provenance --users 1 --mode pilot --seconds 10
# Candidate arm: replace --baseline with --candidate PATH_TO_ACTIONS_ARTIFACT_JSON
```

The runner verifies the direct-origin HTTPS route, starts a bounded SSH control session, and waits for the guarded fixture reset/migration and authenticated smoke. That session holds the host lock and retains the recovery journal for the entire workload. A second controller cannot inspect/mutate the target during the campaign. Normal completion, browser failure, malformed completion, timeout, stdin disconnect and handled termination signals restore the previous database/image before releasing the lock. An uncatchable kill or machine loss leaves the journal for `benchmark_rollout.py recover`. Legacy tools refuse mutation instead of bypassing the lock. Never reinstall the historical `remote.py` during a campaign.

Public metadata records the selected application commit, digest, Checks/publication identity, historical fixture source commit/image/archive hash, workload and private manifest hashes, post-migration table/migration inventory, pool/resource limits, direct network route, pinned k6 image and controller/runner hashes. Actor identities, passwords, cookies and record contents are excluded. Raw browser output and private fixture files remain under ignored `.local/`. Host and generator resource samples are recorded separately. The host-side `operations/OPERATION_ID/campaign.json` survives a disconnected result stream.

Success requires a zero browser exit, nonzero checked business saves, zero failed checks/business failures, unchanged application identity at completion, and confirmed restoration. A passing pilot establishes the orchestration and functional contract; use repeated baseline/candidate runs with the same workload/resources/instrumentation for performance analysis. Install `benchmark_metrics.py` alongside the session to collect the database observations below.

The [hosted runner rehearsal](../docs/evidence/db-efficiency-benchmark-provenance-2026-11-06.json) ran one user for ten measured seconds, completed six saves with six passing checks, and restored the original 15-record state. A separate real SSH disconnect rehearsal verified concurrent-controller exclusion, legacy-reset refusal and automatic restoration. Candidate/source separation, stale server metadata, partial control input, timeout, failed browser checks, incomplete recovery and publication-tag binding are covered by local tests.

## Hosted database observations

[benchmark_metrics.py](benchmark_metrics.py) samples runtime-role backend states/waits, lock counts and pending-outbox age, and captures before/after PostgreSQL database, WAL and cgroup CPU/throttling counters. Reports include observer duration, PostgreSQL settings and container ID/start time. Counter decreases, changed database IDs, reset epochs, restarted containers and changed settings invalidate the deltas. No global statistics are reset. If `pg_stat_statements` is already preloaded and installed, the collector also exports runtime-role counters keyed only by query ID/top-level flag, refusing reset/eviction. It never exports SQL text, parameters, account identities or record values.

The interval starts after guarded preparation/smoke and ends after browser completion. It includes browser startup/login, warmup, idle/background work and observer cost, so it must not be treated as the browser's narrower business-latency window. Database transaction/session counters include the operator sampling connections. Cgroup reads execute brief `cat` processes inside the measured containers. [PostgreSQL cumulative counters can lag backend work](https://www.postgresql.org/docs/16/monitoring-stats.html#MONITORING-STATS-VIEWS); the collector does not force a flush. State/lock samples are periodic observations, not exact peak values or Ecto checkout/lease measurements. A backend may be idle while application code still holds its connection.

The [initial hosted metrics pilot](../docs/evidence/db-efficiency-hosted-metrics-2026-11-06.json) verifies real collection and restoration using the original historical image. Statement statistics and I/O timing were disabled at that point and are reported as unavailable/off, rather than as measured zeros.

Install `benchmark_metrics_setup.py` with the other controllers, then run `python3 benchmark_metrics_setup.py enable` inside the fixed private benchmark directory. This guarded operation snapshots and verifies the current state, journals recovery, stops benchmark web, and recreates only benchmark PostgreSQL with the exact approved statistics flags. It installs the extension in the private `instantflow_benchmark_metrics` schema, denies runtime-role schema access, verifies unchanged public application inventory, and restarts/smoke-tests web. Existing unmanaged extensions/schemas are refused. Failure restores the previous database command; interruption blocks other operations until `python3 benchmark_metrics_setup.py recover` completes. Neither command changes unrelated stacks. Frozen fixture and matching snapshot restoration reinstall the managed extension when instrumentation is enabled.

Operator `psql`, dump and restore clients disable their own statement tracking through session options; application-role statement counters exclude those clients. Database-wide counters still include observer transactions. The [statement-statistics rehearsal](../docs/evidence/db-efficiency-statement-statistics-2026-11-06.json) verified enablement, a checked browser pilot and restoration on the host. Both comparison arms must retain these same settings. No capacity claim follows from a one-user ten-second pilot.
