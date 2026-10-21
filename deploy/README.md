# Push-to-deploy on the Oracle VPS

This matches the workspace's private `deploy/oracle-caddy` stack: GitHub Actions builds an ARM64 image, publishes to GHCR, then connects over SSH to replace only Instantflow.

A push to `main` (or manually running **Checks** on `main`) runs the existing foundation checks first. Only a successful run calls `deploy.yml`. Pull requests and other branches never deploy. Images use full commit SHA tags; deploys are serialized in Actions and on the host. Runs that are no longer the main branch tip skip the SSH deployment. The web process runs as nobody, without Docker access or operator database credentials. Python execution is explicitly disabled in Compose pending separate gVisor acceptance.

## One-time setup

Source templates are in `deploy/oracle-caddy/`. Install their contents into the private `/home/iago/workspace/deploy/oracle-caddy/` directory, then copy only the Instantflow files to `portfolio-server:/home/ubuntu/apps/oracle-caddy/`. Keep future infrastructure edits in sync with these templates. Do not replace the shared compose.yml, .env, Caddyfile, or other projects.

The installer can prepare the local private directory and generate matching random credentials without printing secrets or changing shared configuration:

```sh
python3 deploy/install.py /home/iago/workspace/deploy/oracle-caddy
```

It preserves existing credentials, refuses partial configuration or conflicting project files, and starts no services. Copy only its two Instantflow configuration files and three private environment files to the matching VPS paths. Avoid syncing unrelated deployment changes. Alternatively, create the following private files from their examples next to the VPS's shared compose.yml:

- `instantflow.db.env`: dedicated PostgreSQL cluster's operator account.
- `instantflow.operator.env`: one-off migration credentials and runtime role password.
- `instantflow.env`: runtime database login and Phoenix secret only.

Generate independent passwords with `openssl rand -hex 32` and the Phoenix secret with `openssl rand -hex 64`. Replace all placeholders. The operator password must match between db and operator files; the runtime password must match both runtime URLs and RUNTIME_DB_PASSWORD. Use `chmod 600` for the three files. Never commit real environment files.

The dedicated database has no published port. The database's initialization account is privileged because existing migrations create roles and security-definer functions; only the migration container receives it. PostgreSQL initialization environment variables apply only when the volume is empty. Changing a password in a file alone does not rotate an existing database login.

On this VPS, the shared backup directory is owned by root. Create Instantflow's private subdirectory once so the deployment SSH user can write its snapshots:

```sh
ssh portfolio-server 'sudo install -d -m 700 -o ubuntu -g ubuntu /home/ubuntu/apps/oracle-caddy/backups/instantflow'
```

In GitHub repository `iagobg/instantflow`, open **Settings → Secrets and variables → Actions**, select **New repository secret**, and add the following secrets. This uses repository Actions secrets like the other workspace projects; no GitHub Environment or environment approval gate is required.

| Secret | Value |
| --- | --- |
| DEPLOY_HOST | 134.65.245.186 |
| DEPLOY_USER | ubuntu |
| DEPLOY_PATH | /home/ubuntu/apps/oracle-caddy |
| DEPLOY_SSH_KEY | A private SSH deployment key whose public key is authorized on the VPS |
| DEPLOY_KNOWN_HOSTS | Verified known_hosts entry for the VPS (host key, not the login public key) |

If you previously saved these secrets under a `production` environment, add them as repository secrets instead: the workflow no longer selects that environment. Keep database passwords and Phoenix runtime secrets in the private VPS environment files described above.

Verify the host fingerprint through the existing trusted SSH connection before copying a known_hosts entry. Do not rely on an unverified CI-time ssh-keyscan. The deployment user needs noninteractive `sudo docker compose` access, matching the existing projects.

The workflow uses GITHUB_TOKEN to publish; no registry write token is needed. If the GHCR package is private, authenticate the VPS's **root Docker client** once using a token with read:packages, matching the existing private stack. For public packages no registry login is needed.

Point `instantflow.iagobussoletti.com.br` DNS to the VPS. Install `caddy-sites/instantflow.caddy`. After the first successful deployment, validate and reload Caddy:

```sh
cd /home/ubuntu/apps/oracle-caddy
sudo docker compose -f compose.yml exec -T caddy caddy validate --config /etc/caddy/Caddyfile
sudo docker compose -f compose.yml exec -T caddy caddy reload --config /etc/caddy/Caddyfile
curl --fail https://instantflow.iagobussoletti.com.br/entrar
```

Caddy already imports the sites directory; routine redeploys need no reload. Do not enable a DNS proxy that changes websocket/origin behavior without testing LiveView.

## Deployment sequence and failure handling

`deploy/redeploy.sh DEPLOY_PATH ghcr.io/iagobg/instantflow:<full-sha>` is streamed from the checked-out Actions revision to the VPS; no application source checkout is needed there.

1. Acquire a host lock and verify private configuration exists.
2. Pull the exact application image and PostgreSQL image before stopping the app.
3. Ensure the dedicated database is healthy.
4. Save a private custom-format pg_dump under `backups/instantflow/`.
5. Stop only Instantflow for the forward-only migration window.
6. Run `Instantflow.Release.migrate()` in a disposable operator container. This migrates using OperatorRepo and sets the non-owner runtime role's password without starting the web application.
7. Start the web container and wait for its local HTTP health check.
8. Record the successful image in `instantflow.image.env`, leaving the shared .env untouched.

The health check verifies the login HTTP endpoint. The application's startup role check also queries PostgreSQL and rejects privileged web credentials. CI failure or pull failure leaves the running application alone. Migration failure leaves it stopped for operator intervention; health failure marks the workflow failed. There is no automatic database downgrade or rollback across schema changes.

For manual Compose operations, load the recorded image file as well as the shared environment:

```sh
sudo docker compose --env-file .env --env-file instantflow.image.env \
  -f compose.yml -f projects/instantflow.compose.yml ps
sudo docker compose --env-file .env --env-file instantflow.image.env \
  -f compose.yml -f projects/instantflow.compose.yml logs --tail 100 instantflow
```

For an image rollback, run the deployment script with a previously published SHA **only after confirming schema compatibility**. It still takes a backup and runs pending migrations; it never downgrades the database. Recovery after incompatible migrations requires a planned database restore and maintenance window.

Backups are local pre-deploy snapshots, retained until the operator removes them. Monitor disk use and arrange encrypted off-host copies and restore rehearsals before relying on them for production recovery. No automatic deletion is configured.

Fresh deployments create an empty application database. Do not run demonstration seeds in production. Use the existing organization/bootstrap operator procedures in `docs/organizations-operations.md` to create synthetic demonstration accounts.

## Verification

Run `mix precommit`, `python3 -m unittest discover -s deploy -p 'test_*.py' -v`, and `bash -n deploy/redeploy.sh`. Build on ARM64 with `docker build -t instantflow:smoke .`; local x86 releases cannot validate the VPS architecture. Validate Compose using placeholder env files in an isolated directory with `docker compose ... config --quiet` before copying real configuration.
