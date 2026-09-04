#!/bin/sh
set -eu

: "${PDNS_DB_NAME:?PDNS_DB_NAME is not set}"
: "${PDNS_DB_USER:?PDNS_DB_USER is not set}"
: "${PDNS_DB_PASSWORD:?PDNS_DB_PASSWORD is not set}"
: "${PDNS_API_KEY:?PDNS_API_KEY is not set}"

# `=` not `:=` on purpose: an explicitly empty PDNS_ALSO_NOTIFY must stay empty
# (that is how local verification stops NOTIFY from leaving the machine).
# Only a genuinely unset variable gets the HE address. compose.yml normally
# supplies it; this is the fallback for running the image on its own.
: "${PDNS_ALSO_NOTIFY=216.218.130.2}"
export PDNS_ALSO_NOTIFY

: "${PDNS_WEBSERVER_ALLOW_FROM:=127.0.0.1,::1,172.16.0.0/12}"
export PDNS_WEBSERVER_ALLOW_FROM

echo "[entrypoint] rendering /etc/pdns/pdns.conf"

# Explicit variable list: without it envsubst would also expand any other $VAR
# that ends up in the template (e.g. inside a password).
envsubst '${PDNS_DB_NAME} ${PDNS_DB_USER} ${PDNS_DB_PASSWORD} ${PDNS_API_KEY} ${PDNS_ALSO_NOTIFY} ${PDNS_WEBSERVER_ALLOW_FROM}' \
  < /etc/pdns/pdns.conf.template > /etc/pdns/pdns.conf
chmod 600 /etc/pdns/pdns.conf

echo "[entrypoint] starting PowerDNS (loglevel=$(grep -m1 '^loglevel=' /etc/pdns/pdns.conf | cut -d= -f2))"

# No --guardian: it forks a supervisor that becomes PID 1, which duplicates
# Docker's own supervision, hides crashes from `restart: unless-stopped`, and
# breaks SIGTERM propagation on shutdown.
exec /usr/local/sbin/pdns_server --config-dir=/etc/pdns
