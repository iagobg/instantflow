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
