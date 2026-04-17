#!/bin/sh
set -eu

READY_FILE="/tmp/docai-ready"
STATUS_FILE="/tmp/docai-status"
ERROR_FILE="/tmp/docai-error"
LOG_TARGET="/proc/1/fd/1"
CURRENT_STEP="initializing"

log() {
  message="$(date -u +"%Y-%m-%dT%H:%M:%SZ") [docai-post-start] $*"
  printf '%s\n' "$message"
  if [ -w "$LOG_TARGET" ]; then
    printf '%s\n' "$message" > "$LOG_TARGET"
  fi
}

fail() {
  reason="$*"
  printf '%s\n' "$reason" > "$ERROR_FILE"
  printf 'failed %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$STATUS_FILE"
  log "$reason"
  exit 1
}

on_exit() {
  exit_code="$1"
  if [ "$exit_code" -ne 0 ] && [ ! -f "$ERROR_FILE" ]; then
    printf 'startup failed during: %s\n' "$CURRENT_STEP" > "$ERROR_FILE"
    printf 'failed %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$STATUS_FILE"
    log "Hook exited unexpectedly during: $CURRENT_STEP"
  fi
}

trap 'on_exit $?' EXIT

api_request() {
  method="$1"
  url="$2"
  response_file="$(mktemp)"
  http_code="$(curl -sS -o "$response_file" -w '%{http_code}' -X "$method" -H "Authorization: Bearer $ACCESS_TOKEN" "$url" || true)"
  response_body="$(cat "$response_file" 2>/dev/null || true)"
  rm -f "$response_file"

  if [ -z "$http_code" ] || [ "$http_code" -ge 400 ]; then
    log "API request failed: method=$method url=$url status=${http_code:-none} body=${response_body:-empty}"
    return 1
  fi

  printf '%s' "$response_body"
}

require_env() {
  var_name="$1"
  eval "var_value=\${$var_name:-}"
  if [ -z "$var_value" ]; then
    log "Missing required environment variable: $var_name"
    printf 'missing env: %s\n' "$var_name" > "$ERROR_FILE"
    exit 1
  fi
}

fetch_state() {
  processor_id="$1"
  api_request "GET" "https://${GOOGLE_CLOUD_LOCATION}-documentai.googleapis.com/v1/projects/${GOOGLE_CLOUD_PROJECT}/locations/${GOOGLE_CLOUD_LOCATION}/processors/${processor_id}" \
    | sed -n 's/.*"state": *"\([^"]*\)".*/\1/p' | head -n 1
}

wait_for_state() {
  processor_id="$1"
  desired_state="$2"
  attempts="${3:-18}"
  delay_seconds="${4:-5}"
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

  log "Processor $processor_id did not reach state $desired_state in time"
  printf 'processor %s failed to reach %s\n' "$processor_id" "$desired_state" > "$ERROR_FILE"
  return 1
}

rm -f "$READY_FILE" "$ERROR_FILE"
printf 'starting %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$STATUS_FILE"

log "Starting Doc AI lifecycle post-start hook"
CURRENT_STEP="validate environment"
require_env "GOOGLE_APPLICATION_CREDENTIALS"
require_env "GOOGLE_CLOUD_PROJECT"
require_env "GOOGLE_CLOUD_LOCATION"
require_env "DOC_AI_PROCESSOR_IDS"

if [ ! -r "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
  fail "Credentials file is not readable: $GOOGLE_APPLICATION_CREDENTIALS"
fi

CURRENT_STEP="authenticate with Google Cloud"
log "Authenticating with Google Cloud"
if ! gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS" --quiet >/dev/null 2>&1; then
  fail "Google Cloud authentication failed"
fi
ACCESS_TOKEN="$(gcloud auth print-access-token)"

processor_count=0
for ID in $(printf '%s' "$DOC_AI_PROCESSOR_IDS" | tr ',' ' '); do
  [ -n "$ID" ] || continue
  processor_count=$((processor_count + 1))
  CURRENT_STEP="inspect processor $ID"
  current_state="$(fetch_state "$ID" || true)"
  log "Processor $ID current state: ${current_state:-unknown}"

  if [ "$current_state" != "ENABLED" ]; then
    CURRENT_STEP="enable processor $ID"
    log "Requesting enable for processor $ID"
    if ! api_request "POST" "https://${GOOGLE_CLOUD_LOCATION}-documentai.googleapis.com/v1/projects/${GOOGLE_CLOUD_PROJECT}/locations/${GOOGLE_CLOUD_LOCATION}/processors/${ID}:enable" >/dev/null; then
      fail "Unable to enable processor $ID"
    fi
    CURRENT_STEP="wait for processor $ID"
    wait_for_state "$ID" "ENABLED" || fail "Processor $ID did not reach ENABLED state"
    log "Processor $ID is enabled"
  else
    log "Processor $ID is already enabled"
  fi
done

if [ "$processor_count" -eq 0 ]; then
  fail "No processor IDs were supplied"
fi

printf 'ready %s processors=%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$processor_count" > "$READY_FILE"
printf 'ready %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$STATUS_FILE"
log "Doc AI lifecycle post-start hook completed successfully"
