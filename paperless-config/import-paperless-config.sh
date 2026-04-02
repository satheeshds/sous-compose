#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PAPERLESS_URL=${PAPERLESS_URL:-http://localhost:8000}
PAPERLESS_ADMIN_USER=${PAPERLESS_ADMIN_USER:-admin}
PAPERLESS_ADMIN_PASSWORD=${PAPERLESS_ADMIN_PASSWORD:-password}

map_endpoint() {
  local file_name=$1

  case "$file_name" in
    custom_fields_*.json)
      printf '%s\n' "custom_fields"
      ;;
    document_types_*.json)
      printf '%s\n' "document_types"
      ;;
    tags_*.json)
      printf '%s\n' "tags"
      ;;
    workflow_*.json)
      printf '%s\n' "workflows"
      ;;
    *)
      return 1
      ;;
  esac
}

post_file() {
  local file_path=$1
  local file_name
  local endpoint
  local response
  local body
  local status

  file_name=$(basename "$file_path")
  endpoint=$(map_endpoint "$file_name") || {
    printf 'Skipping unsupported file: %s\n' "$file_name" >&2
    return 0
  }

  response=$(curl -sS \
    -w $'\n%{http_code}' \
    -X POST "${PAPERLESS_URL%/}/api/${endpoint}/" \
    -H "Content-Type: application/json" \
    -H "Authorization: Basic $(echo -n "${PAPERLESS_ADMIN_USER}:${PAPERLESS_ADMIN_PASSWORD}" | base64)" \
    --data-binary "@$file_path")

  body=${response%$'\n'*}
  status=${response##*$'\n'}

  if [[ "$status" != "200" && "$status" != "201" ]]; then
    printf 'Import failed for %s -> %s (HTTP %s)\n' "$file_name" "$endpoint" "$status" >&2
    if [[ -n "$body" ]]; then
      printf '%s\n' "$body" >&2
    fi
    return 1
  fi

  printf 'Imported %s -> %s (HTTP %s)\n' "$file_name" "$endpoint" "$status"
}

shopt -s nullglob
json_paths=("$SCRIPT_DIR"/*.json)

mapfile -t json_files < <(
  for file_path in "${json_paths[@]}"; do
    basename "$file_path"
  done | sort
)

if [[ ${#json_files[@]} -eq 0 ]]; then
  printf 'No JSON files found in %s\n' "$SCRIPT_DIR" >&2
  exit 1
fi

for file_name in "${json_files[@]}"; do
  post_file "$SCRIPT_DIR/$file_name"
done