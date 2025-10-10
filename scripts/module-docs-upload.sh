#!/usr/bin/env bash
set -euo pipefail

FORMATS="json,md"
OUT_DIR=".cache/module-docs"
API_ENDPOINT="${WORKER_ENDPOINT:-https://nixos-module-docs-api-staging.exploit.workers.dev}"
CHUNK_SIZE=100
DRY_RUN=false
UPLOAD=false
SUMMARY=false
TARBALL=""
KEEP_EXPORTER=false
SKIP_EXPORT=false

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
  --summary            Print per-namespace stats when jq is available
  --tarball <path>     Create a tar.gz archive of the exported bundle
  --keep-exporter      Preserve the temporary moduleDocsExporter build output
  --skip-export        Skip running the exporter and reuse existing bundle
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
  --summary)
    SUMMARY=true
    ;;
  --tarball)
    shift
    if [ $# -eq 0 ]; then
      echo "--tarball requires a path" >&2
      exit 1
    fi
    TARBALL="$1"
    ;;
  --keep-exporter)
    KEEP_EXPORTER=true
    ;;
  --skip-export)
    SKIP_EXPORT=true
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
tmp_payload=""
build_args=()
if [ -n "${MODULE_DOCS_NIX_FLAGS:-}" ]; then
  # shellcheck disable=SC2206
  build_args=(${MODULE_DOCS_NIX_FLAGS})
fi
cleanup() {
  if [ -n "$tmp_payload" ] && [ -f "$tmp_payload" ]; then
    rm -f "$tmp_payload"
  fi
  if [ "$KEEP_EXPORTER" != true ] && [ -d "$tmp_exporter" ]; then
    rm -rf "$tmp_exporter"
  fi
}
trap cleanup EXIT
if [ "$SKIP_EXPORT" != true ]; then
  SYSTEM_ATTR=${NIX_SYSTEM:-}
  if [ -z "$SYSTEM_ATTR" ]; then
    SYSTEM_ATTR=$(nix eval --impure --raw --expr 'builtins.currentSystem')
  fi
  EXPORTER_ATTR=".#packages.${SYSTEM_ATTR}.module-docs-exporter"
  nix build "${build_args[@]}" "$EXPORTER_ATTR" -o "$tmp_exporter/result"
  "$tmp_exporter/result/bin/module-docs-exporter" --format "$FORMATS" --out "$OUT_DIR"
else
  echo "Skipping module export; reusing bundle at $OUT_DIR"
fi

JSON_PATH="$OUT_DIR/json/modules.json"
if [ "$SUMMARY" = true ]; then
  if [ ! -f "$JSON_PATH" ]; then
    echo "Summary requested but $JSON_PATH is missing" >&2
  elif command -v jq >/dev/null 2>&1; then
    echo "Namespace summary from $JSON_PATH"
    jq '.namespaces | to_entries[] | { namespace: .key, stats: .value.stats }' "$JSON_PATH"
  else
    echo "Summary requested but jq is not available" >&2
  fi
fi

if [ -n "$TARBALL" ]; then
  mkdir -p "$(dirname "$TARBALL")"
  tar -czf "$TARBALL" -C "$OUT_DIR" .
  echo "Wrote bundle archive to $TARBALL"
fi

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
