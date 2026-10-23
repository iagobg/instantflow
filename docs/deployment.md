# Deployment and operating boundaries

The push-to-deploy setup for the shared Oracle VPS uses ARM64 release images, CI gates, isolated database credentials, pre-migration backups and health checks. Setup and operating instructions are in [deploy/README.md](../deploy/README.md).

GitHub setup follows the other workspace projects: configure repository Actions secrets, with no GitHub Environment required. The workflow uses `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_PATH`, and `DEPLOY_SSH_KEY`, plus `DEPLOY_KNOWN_HOSTS` to verify the VPS SSH identity. Pushes to `main` deploy after the Checks foundation job passes. The database migration and backup steps are application-specific; they do not require environment-scoped GitHub secrets or approval gates.

The demonstrated architecture is one Phoenix service and shared PostgreSQL with mandatory organization scopes/RLS, organization-local profiles, immutable published versions and durable simulated delivery. The local verification used PostgreSQL 16.15 and the pinned OTP 28 / Elixir 1.19.5 runtime.

## VPS verification

On 2026-10-21, the ARM64 image for commit `31e5f48080bf1ab80a09e8e2b3cad470c759adf3` passed hosted foundation checks and image publication. The first VPS startup was then verified using the corrected deployment script: a private database backup completed, all migrations ran through OperatorRepo, and the non-owner web service became healthy. Caddy obtained a Let's Encrypt certificate and the public [login page](https://instantflow.iagobussoletti.com.br/entrar) returned HTTP 200. PostgreSQL has no published host port and uses an internal Docker network. Python execution remains disabled. No accounts or demonstration seeds were installed in the new database.

## Build and start

~~~sh
mix deps.get --check-locked
mix precommit
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
~~~

Production asset deployment compiles the application before bundling LiveView's generated colocated-hook modules, then digests assets. A clean production build and release boot were exercised; the login page and two digested JS/CSS assets returned HTTP 200 using the non-owner runtime role on loopback. [Release evidence](evidence/sprint07-release.json).

Use an operator source checkout or controlled migration job with the same code revision to run mix ecto.migrate -r Instantflow.OperatorRepo and mix instantflow.db_roles before starting the release. Take a private backup and rehearse first. These forward-only migrations require a maintenance window; no rolling mixed-schema deployment is claimed. Demo seeds refuse production mode.

The web service requires DATABASE_URL authenticating as instantflow_runtime, SECRET_KEY_BASE, PHX_HOST and PHX_SERVER=true. PORT defaults to 4000; POOL_SIZE defaults to 10. Supply actual values through the deployment secret store/process environment, never committed files or URLs in logs. RUNTIME_DB_PASSWORD belongs to the operator role-creation task and must match the serving URL. OPERATOR_DATABASE_URL belongs only to a migration/operator job; OperatorRepo is not supervised by the web application. Startup rejects an owner/superuser/BYPASSRLS/CREATEROLE runtime identity.

Start the built release with _build/prod/rel/instantflow/bin/instantflow start. Place it behind the operator's HTTPS reverse proxy, configure PHX_HOST/origin correctly, and restrict direct listener/database exposure. Production uses secure cookies and force-SSL handling of the forwarded protocol. The proxy must own trustworthy forwarded headers, TLS certificates and websocket forwarding. Configure database transport security for the actual topology; remote database TLS and a live reverse proxy were not exercised locally.

## Polling, capacity and reconciliation

The application setting delivery_poll_interval_ms defaults to 250 ms after the measured one-second poll exceeded the committed-visibility target. delivery_batch_per_organization defaults to 20 and max_pending_deliveries_per_organization to 1000. A busy organization receives at most one bounded batch per pass before the next poll. Ordinary business refreshes coalesce through a durable ticket revision checkpoint; every selected intent retains an immutable attempt. Checkpoint and attempts commit together, and delivery-result invalidations always run even when the ticket revision is unchanged. Ticket-before-message lock ordering is shared with retries. Exhaustion rolls back business state/history/receipts atomically. Private files are bounded at 5 MiB and 20 active objects per request, quarantined and manually released, and expire after 30 synthetic-demo days.

Live sessions reauthorize current global session, organization status, local membership, assignment and section rights on commands/refresh. A 30-second reconciliation/revalidation interval covers missed invalidations. Topics carry data-free invalidations; presence never authorizes edits. Monitor outbox pending/failed counts, command error/latency rates, connection/pool wait, database disk, failed role checks and backup freshness. Avoid logging field values, tokens, uploaded content or counselor diagnostics. SQL parameter logging and browser server-log streaming are disabled.

The [load report](performance.md) specifies the workload and hardware. Its numbers are local measurements, not a guarantee for every command mix, arbitrary templates, hosted infrastructure or real network. Repeat the harness and recovery rehearsal on the chosen infrastructure before setting deployment objectives or expanding capacity. Per-organization timezones default to America/Sao_Paulo; instants remain UTC and date-only fields remain dates.

## Backup, restore and lifecycle

Follow [organization operations](organizations-operations.md) for provisioning, audited suspension/resumption and independent administrator bootstrap. Suspension coordinates with in-flight commands/results; it does not delete another school or lose pending intents. Separate CLI invalidations are covered by reconciliation because a CLI process does not share the web node's in-memory PubSub automatically.

Keep whole-database backups private and outside Git. The populated [delivery rehearsal](../scripts/rehearse_delivery.exs) verifies files, budget history, assignments, guardian links, immutable versions, receipts and pending work across two organizations. A full restore affects every organization and may discard post-backup work; verify an isolated restore and plan cutover explicitly. This delivery does not implement tenant-selective restore, off-host encrypted backup policy, key rotation, retention of backup snapshots, production recovery-time/recovery-point objectives or automatic disaster recovery.

## Remaining production readiness

This demonstration has no real payment/order/message/provisioning integrations, real student records, clinical/emergency guarantee or automatic customer code execution. Password recovery, login throttling, MFA, session cleanup, professional accessibility/device review, malware scanning/document authenticity, guardian disputes, production finance controls and operating/support ownership remain separate work. Private files use bounded structural checks and staff attestation, not antivirus. Incident parents receive no internal record projection; only an explicit curated simulated contact/message is recorded.

The serving Phoenix OS account must not receive operator credentials, Docker access or runtime-administration privileges. Sprint 08 uses a constrained authenticated loopback broker; application execution remains disabled by default pending actual host verification. A subprocess or ordinary container is not accepted as the uploaded-code boundary.

The intended future deployment is a private university demonstration on the user's VPS, with access credentials held only by the user and synthetic data rather than real clients. Uploaded scripts remain in scope. The user explicitly approved same-VM gVisor execution, revising the original separate-host requirement; see the [readiness assessment](python-readiness.md) and [operator guide](python-calculations.md).

The user reports Oracle Ampere A1 ARM running Ubuntu with 4 OCPUs and 24 GB RAM, colocating Phoenix and PostgreSQL. This is now the approved topology for a separately permissioned gVisor broker process and bounded workloads. A sandbox escape could reach the application host. No remote capacity, Ubuntu/kernel version or containment has been verified; local controller/application tests do not certify that deployment.

## Sprint 11 restoration readiness

The [supported-data rehearsal](sprint11-scale-recovery-checkpoint.md) verifies empty-org public setup and an exact all-table restore separately from D-32 historical preservation. Use a new isolated database for rehearsal; never reset the serving environment. After restoring or bulk importing, apply the operator migrations, refresh PostgreSQL planner statistics with ANALYZE, then verify runtime-role RLS, current grants, pinned records, private bytes, receipt replay and day totals before traffic. Retired jobs remain cancelled with audit; supported queued jobs retain their current-eligibility and authorized retry checks. Do not blindly replay retired effects. Final load acceptance remains separate, and must use the production asset/profile; development reload/check overhead is retained as a failed diagnostic phase.

## Sprint 11 acceptance handoff — 2026-10-23

The [acceptance report](sprint11-final-acceptance.md) separates the full supported
builder backup/restore rehearsal from the D-32 historical-data rehearsal. Restore
with the operator role, apply forward migrations, establish planner statistics
with ANALYZE after restore/bulk import, and verify scoped runtime reads before
traffic. Additive read indexes were tested only in disposable databases; this
checkpoint does not apply migrations or deploy a serving environment. Supported
curated retries use current authority; never replay retired pending effects.

Production-digested browser assets are the measured profile. Workstation p95 is
not a hosting guarantee: S14 rechecks capacity and recovery on the actual host.
S13 still owns unsent-draft recovery and physical Windows/POS-80 validation.
