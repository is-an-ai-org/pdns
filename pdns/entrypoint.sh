#!/bin/sh
set -eu

: "${PDNS_DB_NAME:?PDNS_DB_NAME is not set}"
: "${PDNS_DB_USER:?PDNS_DB_USER is not set}"
: "${PDNS_DB_PASSWORD:?PDNS_DB_PASSWORD is not set}"
: "${PDNS_API_KEY:?PDNS_API_KEY is not set}"

echo "[entrypoint] rendering /etc/pdns/pdns.conf"

# Explicit variable list: without it envsubst would also expand any other $VAR
# that ends up in the template (e.g. inside a password).
envsubst '${PDNS_DB_NAME} ${PDNS_DB_USER} ${PDNS_DB_PASSWORD} ${PDNS_API_KEY}' \
  < /etc/pdns/pdns.conf.template > /etc/pdns/pdns.conf
chmod 600 /etc/pdns/pdns.conf

echo "[entrypoint] starting PowerDNS (loglevel=$(grep -m1 '^loglevel=' /etc/pdns/pdns.conf | cut -d= -f2))"

# No --guardian: it forks a supervisor that becomes PID 1, which duplicates
# Docker's own supervision, hides crashes from `restart: unless-stopped`, and
# breaks SIGTERM propagation on shutdown.
exec /usr/local/sbin/pdns_server --config-dir=/etc/pdns
