#!/bin/bash
# Periodic pg_dump. Runs as its own service so there is no host cron to drift.
#
# What this protects: every record in the served zones, plus the hmac-sha256
# TSIG keys in `tsigkeys` that authorise AXFR to the secondaries. Losing a TSIG
# key means re-keying that zone with the provider by hand.
# If DNSSEC is ever enabled, `cryptokeys` lands here too and this becomes the
# only copy of the signing keys.
set -euo pipefail

INTERVAL="${BACKUP_INTERVAL:-86400}"
KEEP="${BACKUP_KEEP:-14}"
OUT=/backups

log() { echo "[backup] $(date -Iseconds) $*"; }

log "started (interval=${INTERVAL}s keep=${KEEP})"

while true; do
  ts=$(date +%F-%H%M%S)
  tmp="${OUT}/.pdns-${ts}.sql.gz.partial"
  final="${OUT}/pdns-${ts}.sql.gz"

  if pg_dump --no-owner --no-privileges | gzip -9 > "$tmp"; then
    # Only publish under the real name once the dump succeeded, so a crashed
    # run never leaves a truncated file that looks like a valid backup.
    mv "$tmp" "$final"
    sha256sum "$final" | awk '{print $1}' > "${final}.sha256"
    log "wrote $(basename "$final") ($(du -h "$final" | cut -f1))"

    ls -1t "${OUT}"/pdns-*.sql.gz 2>/dev/null | tail -n "+$((KEEP+1))" | while read -r old; do
      rm -f "$old" "${old}.sha256"
      log "pruned $(basename "$old")"
    done
  else
    rm -f "$tmp"
    log "ERROR: pg_dump failed"
  fi

  sleep "$INTERVAL"
done
