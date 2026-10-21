# Deployment and operating boundaries

The demonstrated architecture is one Phoenix service and shared PostgreSQL with mandatory organization scopes/RLS, organization-local profiles, immutable published versions and durable simulated delivery. The local verification used PostgreSQL 16.15 and the pinned OTP 28 / Elixir 1.19.5 runtime. No external deployment was performed.

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

The ordinary deployment must not receive operator credentials or Python-execution privileges. Optional Sprint 08 remains gated until a concrete calculation, isolated execution hosting, cost/data boundaries, patch/security owner and kill-switch/recovery procedure are established. A subprocess or ordinary shared-host container is not accepted as that readiness evidence.
