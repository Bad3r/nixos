#!/usr/bin/env bash
# Extract NixOS modules documentation and upload to Cloudflare Worker API

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_ROOT}/.cache/module-docs"
OUTPUT_FILE="${OUTPUT_DIR}/modules-extracted.json"
WORKER_ENDPOINT="${WORKER_ENDPOINT:-http://localhost:8787}"

# Functions
log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Step 1: Extract modules using Nix
extract_modules() {
  log_info "Extracting NixOS modules documentation..."
  log_info "Invoking nix eval for scripts/extract-nixos-modules.nix (impure)"

  cd "$PROJECT_ROOT"
  mkdir -p "$OUTPUT_DIR"

  if nix eval \
    --impure \
    --json \
    --expr "(import $SCRIPT_DIR/extract-nixos-modules.nix { flakeRoot = ./.; })" \
    >"$OUTPUT_FILE"; then

    log_info "Modules extracted successfully to $OUTPUT_FILE"

    # Show statistics
    if command -v jq &>/dev/null; then
      local total extracted failed rate
      total=$(jq -r '.stats.total' "$OUTPUT_FILE")
      extracted=$(jq -r '.stats.extracted' "$OUTPUT_FILE")
      failed=$(jq -r '.stats.failed' "$OUTPUT_FILE")
      rate=$(jq -r '.stats.extractionRate' "$OUTPUT_FILE")

      log_info "Extraction statistics:"
      log_info "  Total modules: $total"
      log_info "  Successfully extracted: $extracted"
      log_info "  Failed: $failed"
      log_info "  Success rate: ${rate}%"

      # Show namespaces
      log_info "Namespaces found:"
      jq -r '.namespaces | keys[]' "$OUTPUT_FILE" | while read -r ns; do
        local count
        count=$(jq -r ".namespaces[\"$ns\"].moduleCount" "$OUTPUT_FILE")
        echo "    - $ns: $count modules"
      done
    else
      log_warn "jq not installed, cannot display statistics"
    fi
  else
    log_error "Failed to extract modules"
    return 1
  fi
}

# Step 2: Transform for API upload
transform_for_api() {
  log_info "Transforming data for API upload..."

  if ! command -v jq &>/dev/null; then
    log_error "jq is required for transformation"
    return 1
  fi

  # Transform the extracted data into the format expected by the API
  jq '
    def maybe($k; $v):
      if $v == null then {} else { ($k): $v } end;

    def nonempty_object($v):
      if ($v // {}) == {} then null else $v end;

    def build_option:
      { name: .key }
      + maybe("type"; .value.type)
      + maybe("description"; .value.description)
      + maybe("default_value"; .value.default)
      + maybe("example"; .value.example)
      + maybe("read_only"; .value.readOnly)
      + maybe("internal"; .value.internal);

    {
      modules:
        (.modules | map(
          { namespace, name, path }
          + maybe("description"; .description)
          + (if (.options // {}) == {} then {}
             else { options: (.options | to_entries | map(build_option)) }
            end)
          + maybe("metadata"; nonempty_object(.meta))
        ))
    }
  ' "$OUTPUT_FILE" >"${OUTPUT_FILE}.api.json"

  log_info "Transformed data saved to ${OUTPUT_FILE}.api.json"
}

# Helper: Upload single chunk with retry logic
upload_chunk_with_retry() {
  local chunk_data="$1"
  local chunk_num="$2"
  local total_chunks="$3"
  local max_attempts=3
  local attempt=1

  log_info "Uploading chunk $chunk_num/$total_chunks..." >&2

  while [ $attempt -le $max_attempts ]; do
    local response_file chunk_file
    response_file=$(mktemp)
    chunk_file=$(mktemp)
    printf '%s' "$chunk_data" >"$chunk_file"
    trap 'rm -f "$response_file" "$chunk_file"' RETURN

    http_code=$(curl -sS -w "%{http_code}" -o "$response_file" -X POST \
      -H "Content-Type: application/json" \
      -H "X-API-Key: $API_KEY" \
      --data-binary @"$chunk_file" \
      "$WORKER_ENDPOINT/api/modules/batch")

    curl_status=$?

    if [ $curl_status -ne 0 ]; then
      log_warn "  curl exited with status $curl_status"
    fi

    if [ "$http_code" = "200" ] || [ "$http_code" = "207" ]; then
      local updated created failed
      if command -v jq &>/dev/null && [ -s "$response_file" ]; then
        updated=$(jq -r '.results.updated' "$response_file" 2>/dev/null || echo "0")
        created=$(jq -r '.results.created' "$response_file" 2>/dev/null || echo "0")
        failed=$(jq -r '.results.failed' "$response_file" 2>/dev/null || echo "0")
      else
        updated=0
        created=0
        failed=0
      fi
      echo "$updated,$created,$failed"
      return 0
    else
      log_warn "  Attempt $attempt/$max_attempts failed (HTTP $http_code)"
    if [ -s "$response_file" ]; then
      log_warn "  Response body:"
      cat "$response_file"
    else
      log_warn "  (empty response body)"
    fi

    if [ "$http_code" = "" ]; then
      log_warn "  curl did not return an HTTP status (possible network error)"
    fi

    if [ $attempt -lt $max_attempts ]; then
      local delay=$((2 ** (attempt - 1)))
      log_info "  Retrying in ${delay}s..."
      sleep $delay
    fi
    fi

    ((attempt++))
  done

  log_error "  Chunk $chunk_num failed after $max_attempts attempts"
  return 1
}

# Step 3: Upload to Worker API with chunking
upload_to_api() {
  log_info "Uploading to Cloudflare Worker API with chunked batches..."

  if [ -z "${API_KEY:-}" ]; then
    if command -v sops &>/dev/null; then
      API_KEY=$(sops -d --extract '["cf_api_token"]' "${PROJECT_ROOT}/secrets/cf-api-token.yaml" 2>/dev/null || true)
    fi
  fi

  if [ -z "${API_KEY:-}" ]; then
    log_error "API_KEY not provided. Set API_KEY env var or populate secrets/cf-api-token.yaml"
    return 1
  fi

  if [ ! -f "${OUTPUT_FILE}.api.json" ]; then
    log_error "Transformed data file not found"
    return 1
  fi

  if ! command -v jq &>/dev/null; then
    log_error "jq is required for chunked uploads"
    return 1
  fi

  # Get total module count
  local total_modules
  total_modules=$(jq '.modules | length' "${OUTPUT_FILE}.api.json")
  local chunk_size="${CHUNK_SIZE:-10}" # Tune via env; stay well below Worker body limits
  local total_chunks=$(((total_modules + chunk_size - 1) / chunk_size))

  log_info "Total modules: $total_modules"
  log_info "Chunk size: $chunk_size modules"
  log_info "Total chunks: $total_chunks"

  # Track aggregate statistics
  local total_updated=0
  local total_created=0
  local total_failed=0
  local chunks_succeeded=0
  local chunks_failed=0

  # Process each chunk
  for ((chunk_idx = 0; chunk_idx < total_chunks; chunk_idx++)); do
    local start_idx=$((chunk_idx * chunk_size))
    local chunk_num=$((chunk_idx + 1))

    # Extract chunk from full dataset
    local chunk_data
    chunk_data=$(jq -c "{modules: .modules[$start_idx:$start_idx+$chunk_size]}" \
      "${OUTPUT_FILE}.api.json")

    # Upload with retry
    if result=$(upload_chunk_with_retry "$chunk_data" "$chunk_num" "$total_chunks"); then
      IFS=',' read -r updated created failed <<<"$result"
      total_updated=$((total_updated + updated))
      total_created=$((total_created + created))
      total_failed=$((total_failed + failed))
      chunks_succeeded=$((chunks_succeeded + 1))
      log_info "  ✓ Chunk $chunk_num: $updated updated, $created created, $failed failed"
    else
      chunks_failed=$((chunks_failed + 1))
      log_error "  ✗ Chunk $chunk_num: Upload failed"
    fi

    # Small delay between chunks to avoid rate limiting
    if [ $chunk_num -lt $total_chunks ]; then
      sleep 1
    fi
  done

  # Final summary
  log_info ""
  log_info "Upload complete!"
  log_info "  Total chunks: $total_chunks"
  log_info "  Succeeded: $chunks_succeeded"
  log_info "  Failed: $chunks_failed"
  log_info "  Modules updated: $total_updated"
  log_info "  Modules created: $total_created"
  log_info "  Modules failed: $total_failed"

  if [ $chunks_failed -gt 0 ]; then
    log_warn "Some chunks failed to upload. Check logs above for details."
    return 1
  fi

  return 0
}

# Step 4: Verify upload
verify_upload() {
  log_info "Verifying upload..."

  # Get stats from API
  local response
  response=$(curl -s "$WORKER_ENDPOINT/api/stats")

  if command -v jq &>/dev/null; then
    local total namespaces
    total=$(echo "$response" | jq -r '.stats.total_modules')
    namespaces=$(echo "$response" | jq -r '.stats.namespaces | length')

    log_info "API statistics:"
    log_info "  Total modules: $total"
    log_info "  Total namespaces: $namespaces"
  else
    echo "$response"
  fi
}

# Main execution
main() {
  log_info "Starting NixOS module extraction and upload process"

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
    --endpoint)
      WORKER_ENDPOINT="$2"
      shift 2
      ;;
    --api-key)
      API_KEY="$2"
      shift 2
      ;;
    --extract-only)
      EXTRACT_ONLY=true
      shift
      ;;
    --upload-only)
      UPLOAD_ONLY=true
      shift
      ;;
    --help)
      cat <<EOF
Usage: $0 [OPTIONS]

Options:
    --endpoint URL     Worker endpoint URL (default: http://localhost:8787)
    --api-key KEY      API key for authentication (default: development-key)
    --extract-only     Only extract modules, don't upload
    --upload-only      Only upload previously extracted modules
    --help            Show this help message

Environment variables:
    WORKER_ENDPOINT    Worker endpoint URL
    API_KEY           API key for authentication

Examples:
    # Extract and upload to local development server
    $0

    # Extract and upload to production
    $0 --endpoint https://nixos-modules.example.com --api-key \$PROD_API_KEY

    # Only extract modules
    $0 --extract-only

    # Upload previously extracted modules
    $0 --upload-only --endpoint https://nixos-modules.example.com
EOF
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
    esac
  done

  # Execute steps
  if [ "${UPLOAD_ONLY:-false}" = "true" ]; then
    transform_for_api
    upload_to_api
    verify_upload
  elif [ "${EXTRACT_ONLY:-false}" = "true" ]; then
    extract_modules
    transform_for_api
  else
    extract_modules
    transform_for_api
    upload_to_api
    verify_upload
  fi

  log_info "Process completed successfully!"
}

# Run main function
main "$@"
