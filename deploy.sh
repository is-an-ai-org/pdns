#!/usr/bin/env bash
# Deploy on the server:  cd <deploy-dir> && ./deploy.sh
#
# This is the ONLY supported way for changes to reach the server. Editing files
# on the host instead means the running config and the repo diverge with nothing
# recording that they have, which is why the dirty-tree check below is fatal
# rather than a warning.
set -euo pipefail

cd "$(dirname "$0")"

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }

[[ -f .env ]] || { red "missing .env (cp .env.example .env)"; exit 1; }
[[ -f runner/.env ]] || { red "missing runner/.env"; exit 1; }

# shellcheck disable=SC1091
set -a; source .env; set +a
: "${DATA_ROOT:?DATA_ROOT must be set in .env}"

# Refuse to run against a dirty tree: a hand-edit on the host is how the running
# config silently stops matching the repo, and `git pull --ff-only` would fail
# confusingly anyway.
if [[ -n "$(git status --porcelain)" ]]; then
  red "working tree is dirty — commit or discard before deploying:"
  git status --short
  exit 1
fi

info "pulling"
git pull --ff-only

info "ensuring data directories under $DATA_ROOT"
mkdir -p "$DATA_ROOT/pgdata" "$DATA_ROOT/backups"

info "building (--pull refreshes base images; a stale cached base layer can"
info "         leave PowerDNS on a version with an open security advisory)"
docker compose build --pull

# The database comes up on its own first, because the gpgsql schema has to
# exist before PowerDNS is any use. Nothing else in this repo creates it: the
# entrypoint only renders pdns.conf, and Postgres initialises an empty
# database. A server whose $DATA_ROOT is new -- a rebuild, a restored host, a
# moved disk -- would otherwise come up "healthy" and serve no zone at all,
# because pg_isready does not look at tables and pdns_control rping only pings
# the control socket. That is the failure this step exists to prevent.
info "starting database"
docker compose up -d pdns-db

info "waiting for database"
for _ in $(seq 30); do
  [[ "$(docker inspect pdns-db --format '{{.State.Health.Status}}' 2>/dev/null)" == "healthy" ]] && break
  sleep 2
done
if [[ "$(docker inspect pdns-db --format '{{.State.Health.Status}}' 2>/dev/null)" != "healthy" ]]; then
  red "pdns-db did not become healthy"; docker compose logs --tail 30 pdns-db; exit 1
fi

# to_regclass returns NULL when the table is absent, so this is idempotent:
# an existing installation prints the table name and the load is skipped.
if [[ -z "$(docker compose exec -T pdns-db \
      psql -tAc "select to_regclass('public.domains')" \
      -U "$PDNS_DB_USER" -d "$PDNS_DB_NAME")" ]]; then
  info "loading PowerDNS gpgsql schema (empty database)"
  # The schema ships inside the PowerDNS image, so it always matches the
  # server version being deployed rather than a copy that drifts in this repo.
  docker run --rm --entrypoint cat is-an-ai/pdns-auth:local \
    /usr/local/share/doc/pdns/schema.pgsql.sql \
    | docker compose exec -T pdns-db \
        psql -v ON_ERROR_STOP=1 -U "$PDNS_DB_USER" -d "$PDNS_DB_NAME" >/dev/null
  grn "schema loaded"
else
  info "schema already present"
fi

# --remove-orphans clears containers left behind by any previous project
# layout, so nothing keeps running outside this compose file.
info "starting"
docker compose up -d --remove-orphans

info "waiting for health"
for _ in $(seq 30); do
  unhealthy=$(docker compose ps --format '{{.Service}} {{.Health}}' \
              | awk '$2!="healthy" && $2!="" {print $1}' || true)
  [[ -z "$unhealthy" ]] && break
  sleep 2
done

docker compose ps
if [[ -n "${unhealthy:-}" ]]; then
  red "not healthy: $unhealthy"
  exit 1
fi
grn "deployed"
