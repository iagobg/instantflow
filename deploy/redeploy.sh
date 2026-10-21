#!/usr/bin/env bash
# Runs over SSH from CI; the VPS does not need a source checkout.
set -euo pipefail
umask 077
cd "${1:?Usage: redeploy.sh DEPLOY_PATH IMAGE}"
image="${2:?An immutable GHCR image is required}"
[[ "$image" =~ ^ghcr\.io/[a-z0-9._/-]+:[a-f0-9]{40}$ ]] || {
  echo "Expected a GHCR image tagged with a full commit SHA" >&2
  exit 1
}
exec 9>.instantflow-deploy.lock
flock -w 600 9
test -s instantflow.env
test -s instantflow.operator.env
test -s instantflow.db.env
test -s projects/instantflow.compose.yml
export INSTANTFLOW_IMAGE="$image"
compose=(sudo -n docker compose -f compose.yml -f projects/instantflow.compose.yml)
# Pull first so a registry failure causes no downtime.
"${compose[@]}" --profile tools pull instantflow instantflow-migrate instantflow-db
"${compose[@]}" up -d --wait --wait-timeout 120 instantflow-db
mkdir -p backups/instantflow
backup="backups/instantflow/$(date -u +%Y%m%dT%H%M%SZ)-${image##*:}.dump"
"${compose[@]}" exec -T instantflow-db sh -c \
  'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$backup"
test -s "$backup"
# Forward-only migrations require maintenance downtime. On failure, leave the
# app stopped rather than serve old code against a partially changed schema.
"${compose[@]}" stop instantflow
"${compose[@]}" --profile tools run --rm --no-deps instantflow-migrate
"${compose[@]}" up -d --no-deps --wait --wait-timeout 120 instantflow
# Keep the shared .env untouched; record the last healthy image separately.
printf 'INSTANTFLOW_IMAGE=%s\n' "$image" > instantflow.image.env.tmp
mv instantflow.image.env.tmp instantflow.image.env
echo "Instantflow deployed: $image"
