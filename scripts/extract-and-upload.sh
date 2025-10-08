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
OUTPUT_FILE="${PROJECT_ROOT}/modules-extracted.json"
WORKER_ENDPOINT="${WORKER_ENDPOINT:-http://localhost:8787}"
API_KEY="${API_KEY:-development-key}"

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

    cd "$PROJECT_ROOT"

    # Run the Nix extraction script
    if nix-instantiate \
        --eval \
        --strict \
        --json \
        -E "import $SCRIPT_DIR/extract-nixos-modules-simple.nix {}" \
        > "$OUTPUT_FILE" 2>/dev/null; then

        log_info "Modules extracted successfully to $OUTPUT_FILE"

        # Show statistics
        if command -v jq &> /dev/null; then
            local total=$(jq -r '.stats.total' "$OUTPUT_FILE")
            local extracted=$(jq -r '.stats.extracted' "$OUTPUT_FILE")
            local failed=$(jq -r '.stats.failed' "$OUTPUT_FILE")
            local rate=$(jq -r '.stats.extractionRate' "$OUTPUT_FILE")

            log_info "Extraction statistics:"
            log_info "  Total modules: $total"
            log_info "  Successfully extracted: $extracted"
            log_info "  Failed: $failed"
            log_info "  Success rate: ${rate}%"

            # Show namespaces
            log_info "Namespaces found:"
            jq -r '.namespaces | keys[]' "$OUTPUT_FILE" | while read -r ns; do
                local count=$(jq -r ".namespaces[\"$ns\"].moduleCount" "$OUTPUT_FILE")
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

    if ! command -v jq &> /dev/null; then
        log_error "jq is required for transformation"
        return 1
    fi

    # Transform the extracted data into the format expected by the API
    jq '
    {
        modules: .modules | map({
            namespace: .namespace,
            name: .name,
            path: .path,
            description: .description,
            option_count: .optionCount,
            options: .options | to_entries | map({
                name: .key,
                type: .value.type,
                description: .value.description,
                default_value: .value.default,
                example: .value.example
            }),
            imports: .imports,
            metadata: {
                generated_at: .generated.timestamp,
                nixpkgs_rev: .generated.nixpkgsRev
            }
        })
    }
    ' "$OUTPUT_FILE" > "${OUTPUT_FILE}.api.json"

    log_info "Transformed data saved to ${OUTPUT_FILE}.api.json"
}

# Step 3: Upload to Worker API
upload_to_api() {
    log_info "Uploading to Cloudflare Worker API..."

    if [ ! -f "${OUTPUT_FILE}.api.json" ]; then
        log_error "Transformed data file not found"
        return 1
    fi

    # Upload using curl
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $API_KEY" \
        -d @"${OUTPUT_FILE}.api.json" \
        "$WORKER_ENDPOINT/api/modules/batch")

    if echo "$response" | grep -q '"success":true'; then
        log_info "Upload successful!"

        if command -v jq &> /dev/null; then
            echo "$response" | jq -r '.message'
            local updated=$(echo "$response" | jq -r '.updated')
            local created=$(echo "$response" | jq -r '.created')
            log_info "  Updated: $updated modules"
            log_info "  Created: $created modules"
        fi
    else
        log_error "Upload failed!"
        echo "$response"
        return 1
    fi
}

# Step 4: Verify upload
verify_upload() {
    log_info "Verifying upload..."

    # Get stats from API
    response=$(curl -s "$WORKER_ENDPOINT/api/stats")

    if command -v jq &> /dev/null; then
        local total=$(echo "$response" | jq -r '.total_modules')
        local namespaces=$(echo "$response" | jq -r '.total_namespaces')

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
                cat << EOF
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