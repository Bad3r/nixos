#!/usr/bin/env bash
# Setup Cloudflare resources and update wrangler.jsonc with actual IDs

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
WORKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$WORKER_DIR/../.." && pwd)"
WRANGLER_CONFIG="$WORKER_DIR/wrangler.jsonc"
WRANGLER_BACKUP="$WORKER_DIR/wrangler.jsonc.backup"
ACCOUNT_SECRET_FILE="$REPO_ROOT/secrets/cf-acc-id.yml"
TOKEN_SECRET_FILE="$REPO_ROOT/secrets/cf-api-token.yml"

load_cloudflare_account_id() {
    if [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
        return
    fi

    if [ ! -f "$ACCOUNT_SECRET_FILE" ]; then
        log_warn "Cloudflare account ID secret not found at $ACCOUNT_SECRET_FILE. Set CLOUDFLARE_ACCOUNT_ID manually."
        return
    fi

    if ! command -v sops &> /dev/null; then
        log_warn "sops is not installed; cannot decrypt Cloudflare account ID. Set CLOUDFLARE_ACCOUNT_ID manually."
        return
    fi

    if account_id=$(sops -d --extract '["cloudflare_account_id"]' "$ACCOUNT_SECRET_FILE" 2>/dev/null); then
        account_id=$(echo "$account_id" | tr -d '\n\r')
        if [ -n "$account_id" ]; then
            export CLOUDFLARE_ACCOUNT_ID="$account_id"
            log_info "Loaded Cloudflare account ID from SOPS secrets"
        else
            log_warn "Cloudflare account ID secret is empty"
        fi
    else
        log_warn "Failed to decrypt Cloudflare account ID from $ACCOUNT_SECRET_FILE"
    fi
}

load_cloudflare_api_token() {
    if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
        return
    fi

    if [ ! -f "$TOKEN_SECRET_FILE" ]; then
        log_warn "Cloudflare API token secret not found at $TOKEN_SECRET_FILE. Set CLOUDFLARE_API_TOKEN manually."
        return
    fi

    if ! command -v sops &> /dev/null; then
        log_warn "sops is not installed; cannot decrypt Cloudflare API token. Set CLOUDFLARE_API_TOKEN manually."
        return
    fi

    if token_value=$(sops -d --extract '["cf_api_token"]' "$TOKEN_SECRET_FILE" 2>/dev/null); then
        token_value=$(echo "$token_value" | tr -d '\n\r')
        if [ -n "$token_value" ]; then
            export CLOUDFLARE_API_TOKEN="$token_value"
            export CF_API_TOKEN="$token_value"
            log_info "Loaded Cloudflare API token from SOPS secrets"
        else
            log_warn "Cloudflare API token secret is empty"
        fi
    else
        log_warn "Failed to decrypt Cloudflare API token from $TOKEN_SECRET_FILE"
    fi
}

load_cloudflare_account_id
load_cloudflare_api_token

if [ -n "${CLOUDFLARE_API_TOKEN:-}" ] && [ -z "${CF_API_TOKEN:-}" ]; then
    export CF_API_TOKEN="$CLOUDFLARE_API_TOKEN"
fi

log_info "Setting up Cloudflare resources for NixOS Module Documentation API"

# Create backup of wrangler.jsonc
cp "$WRANGLER_CONFIG" "$WRANGLER_BACKUP"
log_info "Created backup: $WRANGLER_BACKUP"

# Function to update JSON with jq (if available) or sed
update_config() {
    local key=$1
    local value=$2

    if command -v jq &> /dev/null; then
        # Use jq if available
        echo "Using jq to update $key"
        # Note: jq doesn't handle jsonc comments well, so we'll use sed anyway
        sed -i "s|\"$key\": \"TODO_[^\"]*\"|\"$key\": \"$value\"|g" "$WRANGLER_CONFIG"
    else
        # Use sed for simple replacement
        sed -i "s|\"$key\": \"TODO_[^\"]*\"|\"$key\": \"$value\"|g" "$WRANGLER_CONFIG"
    fi
}

# 1. Create D1 Database for production
log_info "Creating D1 database: nixos-modules-db"
DB_OUTPUT=$(npx wrangler d1 create nixos-modules-db 2>&1 || true)
if echo "$DB_OUTPUT" | grep -q "successfully created"; then
    DB_ID=$(echo "$DB_OUTPUT" | grep -oP '(?<=database_id = ")[^"]+' || echo "$DB_OUTPUT" | grep "database_id" | cut -d'"' -f2)
    log_info "Created D1 database with ID: $DB_ID"
    update_config "database_id" "$DB_ID"
elif echo "$DB_OUTPUT" | grep -q "already exists"; then
    log_warn "D1 database nixos-modules-db already exists"
    # Try to get the ID from list
    DB_ID=$(npx wrangler d1 list --json | jq -r '.[] | select(.name=="nixos-modules-db") | .uuid' 2>/dev/null || echo "EXISTING_DB")
    if [ "$DB_ID" != "EXISTING_DB" ]; then
        log_info "Found existing database ID: $DB_ID"
        update_config "database_id" "$DB_ID"
    fi
else
    log_error "Failed to create D1 database"
    echo "$DB_OUTPUT"
fi

# 2. Create D1 Database for staging
log_info "Creating D1 database: nixos-modules-db-staging"
DB_STAGING_OUTPUT=$(npx wrangler d1 create nixos-modules-db-staging 2>&1 || true)
if echo "$DB_STAGING_OUTPUT" | grep -q "successfully created"; then
    DB_STAGING_ID=$(echo "$DB_STAGING_OUTPUT" | grep -oP '(?<=database_id = ")[^"]+' || echo "$DB_STAGING_OUTPUT" | grep "database_id" | cut -d'"' -f2)
    log_info "Created staging D1 database with ID: $DB_STAGING_ID"
    sed -i "s|\"database_id\": \"TODO_CREATE_STAGING_DB\"|\"database_id\": \"$DB_STAGING_ID\"|g" "$WRANGLER_CONFIG"
elif echo "$DB_STAGING_OUTPUT" | grep -q "already exists"; then
    log_warn "D1 database nixos-modules-db-staging already exists"
    DB_STAGING_ID=$(npx wrangler d1 list --json | jq -r '.[] | select(.name=="nixos-modules-db-staging") | .uuid' 2>/dev/null || echo "EXISTING_DB")
    if [ "$DB_STAGING_ID" != "EXISTING_DB" ]; then
        log_info "Found existing staging database ID: $DB_STAGING_ID"
        sed -i "s|\"database_id\": \"TODO_CREATE_STAGING_DB\"|\"database_id\": \"$DB_STAGING_ID\"|g" "$WRANGLER_CONFIG"
    fi
fi

# 3. Create KV namespace for production
log_info "Creating KV namespace: MODULE_CACHE"
KV_OUTPUT=$(npx wrangler kv:namespace create MODULE_CACHE 2>&1 || true)
if echo "$KV_OUTPUT" | grep -q "id ="; then
    KV_ID=$(echo "$KV_OUTPUT" | grep -oP '(?<=id = ")[^"]+' || echo "$KV_OUTPUT" | grep "id" | head -1 | cut -d'"' -f2)
    log_info "Created KV namespace with ID: $KV_ID"
    sed -i "s|\"id\": \"TODO_RUN_WRANGLER_KV_CREATE\"|\"id\": \"$KV_ID\"|g" "$WRANGLER_CONFIG"
else
    log_warn "KV namespace creation returned unexpected output"
    echo "$KV_OUTPUT"
fi

# 4. Create KV namespace preview for production
log_info "Creating KV namespace preview: MODULE_CACHE"
KV_PREVIEW_OUTPUT=$(npx wrangler kv:namespace create MODULE_CACHE --preview 2>&1 || true)
if echo "$KV_PREVIEW_OUTPUT" | grep -q "id ="; then
    KV_PREVIEW_ID=$(echo "$KV_PREVIEW_OUTPUT" | grep -oP '(?<=id = ")[^"]+' || echo "$KV_PREVIEW_OUTPUT" | grep "id" | head -1 | cut -d'"' -f2)
    log_info "Created KV preview namespace with ID: $KV_PREVIEW_ID"
    sed -i "s|\"preview_id\": \"TODO_RUN_WRANGLER_KV_CREATE_PREVIEW\"|\"preview_id\": \"$KV_PREVIEW_ID\"|g" "$WRANGLER_CONFIG"
fi

# 5. Create KV namespace for staging
log_info "Creating KV namespace: MODULE_CACHE_STAGING"
KV_STAGING_OUTPUT=$(npx wrangler kv:namespace create MODULE_CACHE_STAGING 2>&1 || true)
if echo "$KV_STAGING_OUTPUT" | grep -q "id ="; then
    KV_STAGING_ID=$(echo "$KV_STAGING_OUTPUT" | grep -oP '(?<=id = ")[^"]+' || echo "$KV_STAGING_OUTPUT" | grep "id" | head -1 | cut -d'"' -f2)
    log_info "Created staging KV namespace with ID: $KV_STAGING_ID"
    sed -i "s|\"id\": \"TODO_CREATE_STAGING_KV\"|\"id\": \"$KV_STAGING_ID\"|g" "$WRANGLER_CONFIG"
fi

# 6. Create KV namespace preview for staging
KV_STAGING_PREVIEW_OUTPUT=$(npx wrangler kv:namespace create MODULE_CACHE_STAGING --preview 2>&1 || true)
if echo "$KV_STAGING_PREVIEW_OUTPUT" | grep -q "id ="; then
    KV_STAGING_PREVIEW_ID=$(echo "$KV_STAGING_PREVIEW_OUTPUT" | grep -oP '(?<=id = ")[^"]+' || echo "$KV_STAGING_PREVIEW_OUTPUT" | grep "id" | head -1 | cut -d'"' -f2)
    log_info "Created staging KV preview namespace with ID: $KV_STAGING_PREVIEW_ID"
    sed -i "s|\"preview_id\": \"TODO_CREATE_STAGING_KV_PREVIEW\"|\"preview_id\": \"$KV_STAGING_PREVIEW_ID\"|g" "$WRANGLER_CONFIG"
fi

# 7. Create R2 buckets
log_info "Creating R2 bucket: nixos-module-docs"
npx wrangler r2 bucket create nixos-module-docs 2>&1 || log_warn "R2 bucket nixos-module-docs may already exist"

log_info "Creating R2 bucket: nixos-module-docs-staging"
npx wrangler r2 bucket create nixos-module-docs-staging 2>&1 || log_warn "R2 bucket nixos-module-docs-staging may already exist"

# 8. Set API_KEY secret
log_info "Setting API_KEY secret (you'll be prompted to enter it)"
echo "Enter the API_KEY value (or press Ctrl+C to skip):"
read -s API_KEY
if [ -n "$API_KEY" ]; then
    echo "$API_KEY" | npx wrangler secret put API_KEY
    echo "$API_KEY" | npx wrangler secret put API_KEY --env staging
    log_info "API_KEY secret set for both production and staging"
else
    log_warn "API_KEY not set, you'll need to set it manually later"
fi

# Summary
log_info "Setup complete! Resources created:"
echo -e "${GREEN}✓${NC} D1 Databases"
echo -e "${GREEN}✓${NC} KV Namespaces"
echo -e "${GREEN}✓${NC} R2 Buckets"
echo -e "${GREEN}✓${NC} Updated wrangler.jsonc with actual IDs"

log_info "Next steps:"
echo "1. Review the updated wrangler.jsonc file"
echo "2. Run database migrations: npm run db:migrate"
echo "3. Deploy the worker: npm run deploy"

# Show diff if possible
if command -v diff &> /dev/null; then
    log_info "Changes made to wrangler.jsonc:"
    diff -u "$WRANGLER_BACKUP" "$WRANGLER_CONFIG" || true
fi
