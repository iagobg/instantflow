# Local development and deployment

Develop on a local `codex/...` branch. Run `mix precommit`, the runner and
deployment Python tests, and any focused checks needed for the change.
Fetch the remote, integrate changes, then merge locally into an up-to-date
`main` and push `main`. A GitHub pull request is optional for this solo
university project. Never force-push shared history.

GitHub Actions repeats the foundation checks before building the immutable
ARM64 release and deploying it to the VPS. Check both Actions and the live
health endpoint after pushing. A local merge must not bypass failed checks.
Use local tests for normal iteration; use the VPS for ARM64/gVisor acceptance
and final integration. Avoid using the deployed instance as the only test environment.

The deployment backs up the database and performs forward migrations during
maintenance downtime. A failed migration or health check needs investigation
before another deployment. Keep owner credentials in the one-off operator
environment; the serving application receives only runtime credentials.

Python execution is opt-in. The separately installed broker uses gVisor,
an authenticated Unix socket, pinned images and explicit resource limits.
The reviewed `deploy/instantflow-python.compose.yml` fragment is copied to
the VPS stack's `projects/` directory only after real-host acceptance.
Its private `instantflow.python.env` contains the broker token. The deploy
script includes the fragment only when it exists and requires the socket.
The durable database switch is a further operator-controlled gate.
