#!/usr/bin/env bash
set -euo pipefail

FORMATS="json,md"
OUT_DIR=".cache/module-docs"
API_ENDPOINT="${WORKER_ENDPOINT:-https://nixos-module-docs-api-staging.exploit.workers.dev}"
CHUNK_SIZE=100
DRY_RUN=false
UPLOAD=false

usage() {
  cat <<USAGE
Usage: $0 [options]
  --format <list>      Comma-separated list of formats (json,md)
  --out <dir>          Output directory (default: .cache/module-docs)
  --api-endpoint <url> Upload endpoint (default: $API_ENDPOINT)
  --api-key <key>      API key for authenticated upload
  --chunk-size <n>     Upload chunk size for modules.json payloads (default: 100)
  --upload             Enable upload after export
  --dry-run            Skip upload while still exporting bundles
  --help               Show this message
USAGE
}

API_KEY="${API_KEY:-${MODULE_DOCS_API_KEY:-}}"

while [ $# -gt 0 ]; do
  case "$1" in
  --format)
    shift
    FORMATS="${1:-$FORMATS}"
    ;;
  --out)
    shift
    OUT_DIR="${1:-$OUT_DIR}"
    ;;
  --api-endpoint)
    shift
    API_ENDPOINT="${1:-$API_ENDPOINT}"
    ;;
  --api-key)
    shift
    API_KEY="${1:-}"
    ;;
  --chunk-size)
    shift
    CHUNK_SIZE="${1:-$CHUNK_SIZE}"
    ;;
  --upload)
    UPLOAD=true
    ;;
  --dry-run)
    DRY_RUN=true
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    echo "Unknown argument: $1" >&2
    usage
    exit 1
    ;;
  esac
  shift || true
done

tmp_exporter="$(mktemp -d)"
trap 'rm -rf "$tmp_exporter"' EXIT
nix build --impure .#moduleDocsExporter -o "$tmp_exporter/result"
"$tmp_exporter/result/bin/module-docs-exporter" --format "$FORMATS" --out "$OUT_DIR"

JSON_PATH="$OUT_DIR/json/modules.json"
if [ "$UPLOAD" = true ] && [ "$DRY_RUN" = false ]; then
  if [ -z "$API_KEY" ]; then
    echo "API key required for upload" >&2
    exit 2
  fi
  if [ ! -f "$JSON_PATH" ]; then
    echo "JSON payload not found at $JSON_PATH" >&2
    exit 3
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required for upload streaming" >&2
    exit 4
  fi
  tmp_payload=$(mktemp)
  trap 'rm -f "$tmp_payload"' EXIT
  idx=1
  chunk_count=0
  printf '' >"$tmp_payload"
  emit_chunk() {
    if [ $chunk_count -eq 0 ]; then
      return
    fi
    payload=$(jq -nc --argjson mods "$(cat "$tmp_payload")" '{ modules: $mods }')
    response=$(printf '%s' "$payload" | curl -sS -w "\n%{http_code}" -X POST \
      -H "Content-Type: application/json" \
      -H "X-API-Key: $API_KEY" \
      "$API_ENDPOINT/api/modules/batch")
    body=$(printf '%s' "$response" | head -n 1)
    status=$(printf '%s' "$response" | tail -n 1)
    if [ "$status" != "200" ] && [ "$status" != "207" ]; then
      echo "Upload chunk $idx failed with status $status" >&2
      echo "$body" >&2
      exit 5
    fi
    echo "Uploaded chunk $idx (status $status)"
    idx=$((idx + 1))
    chunk_count=0
    printf '' >"$tmp_payload"
  }

  jq -c '.namespaces | to_entries[] | .value.modules[]' "$JSON_PATH" | while IFS= read -r module_line; do
    if [ $chunk_count -eq 0 ]; then
      printf '[' >"$tmp_payload"
    else
      printf ',' >>"$tmp_payload"
    fi
    printf '%s' "$module_line" >>"$tmp_payload"
    chunk_count=$((chunk_count + 1))
    if [ $chunk_count -ge "$CHUNK_SIZE" ]; then
      printf ']' >>"$tmp_payload"
      emit_chunk
    fi
  done
  if [ $chunk_count -gt 0 ]; then
    printf ']' >>"$tmp_payload"
    emit_chunk
  fi
fi

echo "Artifacts available under $OUT_DIR"
