#!/bin/sh
set -eu

READY_FILE="/tmp/docai-ready"
STATUS_FILE="/tmp/docai-status"
ERROR_FILE="/tmp/docai-error"

log() {
  printf '%s [docai-healthcheck] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*" >&2
}

if [ -f "$ERROR_FILE" ]; then
  log "Failure marker present: $(cat "$ERROR_FILE" 2>/dev/null || printf 'unknown error')"
  exit 1
fi

if [ ! -s "$READY_FILE" ]; then
  if [ -f "$STATUS_FILE" ]; then
    log "Container not ready yet: $(cat "$STATUS_FILE" 2>/dev/null || printf 'status unavailable')"
  else
    log "Container not ready yet"
  fi
  exit 1
fi

if [ ! -r "/config/service-account.json" ]; then
  log "Credentials file is missing or unreadable"
  exit 1
fi

exit 0
