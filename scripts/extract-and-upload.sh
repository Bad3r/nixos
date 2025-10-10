#!/usr/bin/env bash
set -euo pipefail

FORMATS="json,md"
OUT_DIR=".cache/module-docs"
CHUNK_SIZE=""
API_ENDPOINT="${WORKER_ENDPOINT:-https://nixos-module-docs-api-staging.exploit.workers.dev}"
API_KEY="${API_KEY:-${MODULE_DOCS_API_KEY:-}}"
UPLOAD_ONLY=false
EXTRA_ARGS=()

usage() {
  cat <<USAGE
Usage: $0 [options]
  --format <list>      Comma-separated list of formats (default: json,md)
  --out <dir>          Bundle directory (default: .cache/module-docs)
  --endpoint <url>     API endpoint override
  --api-key <key>      API key for authenticated upload
  --chunk-size <n>     Upload chunk size override
  --upload-only        Skip export step and upload existing bundle
  --help               Show this message
USAGE
}

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
  --endpoint)
    shift
    API_ENDPOINT="${1:-$API_ENDPOINT}"
    ;;
  --api-key)
    shift
    API_KEY="${1:-$API_KEY}"
    ;;
  --chunk-size)
    shift
    CHUNK_SIZE="${1:-}"
    ;;
  --upload-only)
    UPLOAD_ONLY=true
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    EXTRA_ARGS+=("$1")
    ;;
  esac
  shift
done

if [ "$UPLOAD_ONLY" = true ] && [ ! -f "$OUT_DIR/json/modules.json" ]; then
  echo "Bundle not found at $OUT_DIR; cannot upload" >&2
  exit 1
fi

cmd=(./scripts/module-docs-upload.sh --format "$FORMATS" --out "$OUT_DIR" --upload)

if [ -n "$API_ENDPOINT" ]; then
  cmd+=("--api-endpoint" "$API_ENDPOINT")
fi

if [ -n "$API_KEY" ]; then
  cmd+=("--api-key" "$API_KEY")
fi

if [ -n "$CHUNK_SIZE" ]; then
  cmd+=("--chunk-size" "$CHUNK_SIZE")
fi

if [ "$UPLOAD_ONLY" = true ]; then
  cmd+=("--skip-export")
fi

cmd+=("${EXTRA_ARGS[@]}")

exec "${cmd[@]}"
