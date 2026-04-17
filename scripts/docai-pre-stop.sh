#!/bin/sh
set -eu

READY_FILE="/tmp/docai-ready"
STATUS_FILE="/tmp/docai-status"
LOG_TARGET="/proc/1/fd/1"

log() {
  message="$(date -u +"%Y-%m-%dT%H:%M:%SZ") [docai-pre-stop] $*"
  printf '%s\n' "$message"
  if [ -w "$LOG_TARGET" ]; then
    printf '%s\n' "$message" > "$LOG_TARGET"
  fi
}

api_request() {
  method="$1"
  url="$2"
  response_file="$(mktemp)"
  http_code="$(curl -sS -o "$response_file" -w '%{http_code}' -X "$method" -H "Authorization: Bearer $ACCESS_TOKEN" "$url" || true)"
  response_body="$(cat "$response_file" 2>/dev/null || true)"
  rm -f "$response_file"

  if [ -z "$http_code" ] || [ "$http_code" -ge 400 ]; then
    log "API request failed during shutdown: method=$method url=$url status=${http_code:-none} body=${response_body:-empty}"
    return 1
  fi

  printf '%s' "$response_body"
}

fetch_state() {
  processor_id="$1"
  api_request "GET" "https://${GOOGLE_CLOUD_LOCATION}-documentai.googleapis.com/v1/projects/${GOOGLE_CLOUD_PROJECT}/locations/${GOOGLE_CLOUD_LOCATION}/processors/${processor_id}" \
    | sed -n 's/.*"state": *"\([^"]*\)".*/\1/p' | head -n 1
}

wait_for_state() {
  processor_id="$1"
  desired_state="$2"
  attempts="${3:-10}"
  delay_seconds="${4:-3}"
  attempt=1

  while [ "$attempt" -le "$attempts" ]; do
    state="$(fetch_state "$processor_id" || true)"
    log "Processor $processor_id state check $attempt/$attempts: ${state:-unknown}"
    if [ "$state" = "$desired_state" ]; then
      return 0
    fi
    attempt=$((attempt + 1))
    sleep "$delay_seconds"
  done

  return 1
}

printf 'stopping %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$STATUS_FILE"
rm -f "$READY_FILE"
log "Starting Doc AI lifecycle pre-stop hook"

if [ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ] || [ ! -r "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]; then
  log "Credentials are unavailable; skipping processor disable"
  exit 0
fi

if [ -z "${GOOGLE_CLOUD_PROJECT:-}" ] || [ -z "${GOOGLE_CLOUD_LOCATION:-}" ] || [ -z "${DOC_AI_PROCESSOR_IDS:-}" ]; then
  log "Required environment variables are missing; skipping processor disable"
  exit 0
fi

if ! gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS" --quiet >/dev/null 2>&1; then
  log "Google Cloud authentication failed during shutdown; skipping processor disable"
  exit 0
fi

ACCESS_TOKEN="$(gcloud auth print-access-token)"

for ID in $(printf '%s' "$DOC_AI_PROCESSOR_IDS" | tr ',' ' '); do
  [ -n "$ID" ] || continue
  current_state="$(fetch_state "$ID" || true)"
  log "Processor $ID current state before disable: ${current_state:-unknown}"

  if [ "$current_state" != "DISABLED" ]; then
    log "Requesting disable for processor $ID"
    if api_request "POST" "https://${GOOGLE_CLOUD_LOCATION}-documentai.googleapis.com/v1/projects/${GOOGLE_CLOUD_PROJECT}/locations/${GOOGLE_CLOUD_LOCATION}/processors/${ID}:disable" >/dev/null; then
      if wait_for_state "$ID" "DISABLED"; then
        log "Processor $ID is disabled"
      else
        log "Processor $ID disable request was sent but did not confirm before shutdown"
      fi
    else
      log "Disable request failed for processor $ID"
    fi
  else
    log "Processor $ID is already disabled"
  fi
done

printf 'stopped %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$STATUS_FILE"
log "Doc AI lifecycle pre-stop hook completed"
