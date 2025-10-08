#!/usr/bin/env bash
# Setup script for NixOS Module Documentation API
# This script creates the required Cloudflare resources and updates wrangler.jsonc

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ACCOUNT_SECRET_FILE="$REPO_ROOT/secrets/cf-acc-id.yaml"
TOKEN_SECRET_FILE="$REPO_ROOT/secrets/cf-api-token.yaml"
MODULE_API_KEY_FILE="$REPO_ROOT/secrets/module-api-key.yaml"
MODULE_API_KEY_FIELD="module_api_key"

load_cloudflare_account_id() {
  if [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
    return
  fi

  if [ ! -f "$ACCOUNT_SECRET_FILE" ]; then
    print_warn "Cloudflare account ID secret not found at $ACCOUNT_SECRET_FILE. Set CLOUDFLARE_ACCOUNT_ID manually."
    return
  fi

  if ! command -v sops &>/dev/null; then
    print_warn "sops is not installed; cannot decrypt Cloudflare account ID. Set CLOUDFLARE_ACCOUNT_ID manually."
    return
  fi

  if account_id=$(sops -d --extract '["cloudflare_account_id"]' "$ACCOUNT_SECRET_FILE" 2>/dev/null); then
    account_id=$(echo "$account_id" | tr -d '\n\r')
    if [ -n "$account_id" ]; then
      export CLOUDFLARE_ACCOUNT_ID="$account_id"
      print_info "Loaded Cloudflare account ID from SOPS secrets"
    else
      print_warn "Cloudflare account ID secret is empty"
    fi
  else
    print_warn "Failed to decrypt Cloudflare account ID from $ACCOUNT_SECRET_FILE"
  fi
}

load_cloudflare_api_token() {
  if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
    return
  fi

  if [ ! -f "$TOKEN_SECRET_FILE" ]; then
    print_warn "Cloudflare API token secret not found at $TOKEN_SECRET_FILE. Set CLOUDFLARE_API_TOKEN manually."
    return
  fi

  if ! command -v sops &>/dev/null; then
    print_warn "sops is not installed; cannot decrypt Cloudflare API token. Set CLOUDFLARE_API_TOKEN manually."
    return
  fi

  if token_value=$(sops -d --extract '["cf_api_token"]' "$TOKEN_SECRET_FILE" 2>/dev/null); then
    token_value=$(echo "$token_value" | tr -d '\n\r')
    if [ -n "$token_value" ]; then
      export CLOUDFLARE_API_TOKEN="$token_value"
      export CF_API_TOKEN="$token_value"
      print_info "Loaded Cloudflare API token from SOPS secrets"
    else
      print_warn "Cloudflare API token secret is empty"
    fi
  else
    print_warn "Failed to decrypt Cloudflare API token from $TOKEN_SECRET_FILE"
  fi
}

load_module_api_key() {
  if [ -n "${MODULE_API_KEY:-}" ]; then
    return
  fi

  if [ ! -f "$MODULE_API_KEY_FILE" ]; then
    print_warn "Module API key secret not found at $MODULE_API_KEY_FILE. Set MODULE_API_KEY manually."
    return
  fi

  if ! command -v sops &>/dev/null; then
    print_warn "sops is not installed; cannot decrypt module API key. Set MODULE_API_KEY manually."
    return
  fi

  if module_key=$(sops -d --extract '["'"$MODULE_API_KEY_FIELD"'"]' "$MODULE_API_KEY_FILE" 2>/dev/null); then
    module_key=$(echo "$module_key" | tr -d '\n\r')
    if [ -n "$module_key" ]; then
      export MODULE_API_KEY="$module_key"
      print_info "Loaded module API key from SOPS secrets"
      return
    fi
  fi

  print_warn "Module API key not found in SOPS secrets; skipping automatic configuration."
}

load_cloudflare_account_id
load_cloudflare_api_token
load_module_api_key

if [ -n "${CLOUDFLARE_API_TOKEN:-}" ] && [ -z "${CF_API_TOKEN:-}" ]; then
  export CF_API_TOKEN="$CLOUDFLARE_API_TOKEN"
fi

# Check if wrangler is installed
if ! command -v wrangler &>/dev/null; then
  print_error "wrangler CLI is not installed. Please install it with: npm install -g wrangler"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  print_error "jq is required for parsing Cloudflare CLI output. Please install jq."
  exit 1
fi

# Check if authenticated
print_info "Checking Cloudflare authentication..."
if ! wrangler whoami &>/dev/null; then
  print_warn "Not authenticated with Cloudflare. Running 'wrangler login'..."
  wrangler login
fi

print_info "Starting Cloudflare resource setup..."

# Create D1 Database
print_info "Creating D1 database..."
D1_OUTPUT=$(npx wrangler d1 create nixos-modules-db 2>&1 || true)
if echo "$D1_OUTPUT" | grep -q "database_id"; then
  D1_ID=$(echo "$D1_OUTPUT" | grep -oE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | head -n 1)
  print_info "D1 Database created with ID: $D1_ID"
elif echo "$D1_OUTPUT" | grep -q "already exists"; then
  print_warn "D1 database 'nixos-modules-db' already exists. Please get the ID manually."
  D1_ID="EXISTING_DB_ID"
else
  print_error "Failed to create D1 database: $D1_OUTPUT"
  D1_ID="TODO_RUN_WRANGLER_D1_CREATE"
fi

# Create KV Namespace
print_info "Creating KV namespace..."
KV_OUTPUT=$(npx wrangler kv namespace create CACHE 2>&1 || true)
if echo "$KV_OUTPUT" | grep -q '"id"'; then
  KV_ID=$(echo "$KV_OUTPUT" | jq -r '.id // empty')
  if [ -z "$KV_ID" ]; then
    KV_ID="TODO_RUN_WRANGLER_KV_CREATE"
  else
    print_info "KV namespace created with ID: $KV_ID"
  fi
elif echo "$KV_OUTPUT" | grep -qi "already exists"; then
  print_warn "KV namespace 'CACHE' already exists. Fetching ID..."
  KV_LIST=$(npx wrangler kv namespace list)
  KV_ID=$(echo "$KV_LIST" | jq -r '.[] | select(.title == "CACHE") | .id' | head -n 1)
  if [ -z "$KV_ID" ]; then
    KV_ID="TODO_RUN_WRANGLER_KV_CREATE"
  fi
else
  print_error "Failed to create KV namespace: $KV_OUTPUT"
  KV_ID="TODO_RUN_WRANGLER_KV_CREATE"
fi

# Create KV Preview Namespace
print_info "Creating KV preview namespace..."
KV_PREVIEW_OUTPUT=$(npx wrangler kv namespace create CACHE --preview 2>&1 || true)
if echo "$KV_PREVIEW_OUTPUT" | grep -q '"id"'; then
  KV_PREVIEW_ID=$(echo "$KV_PREVIEW_OUTPUT" | jq -r '.id // empty')
  if [ -z "$KV_PREVIEW_ID" ]; then
    KV_PREVIEW_ID="TODO_RUN_WRANGLER_KV_CREATE_PREVIEW"
  fi
elif echo "$KV_PREVIEW_OUTPUT" | grep -qi "already exists"; then
  print_warn "KV preview namespace already exists."
  KV_PREVIEW_ID="TODO_RUN_WRANGLER_KV_CREATE_PREVIEW"
else
  KV_PREVIEW_ID="TODO_RUN_WRANGLER_KV_CREATE_PREVIEW"
fi

# Create R2 Bucket
print_info "Creating R2 bucket..."
R2_OUTPUT=$(npx wrangler r2 bucket create nixos-module-docs 2>&1 || true)
if echo "$R2_OUTPUT" | grep -q "Created bucket"; then
  print_info "R2 bucket 'nixos-module-docs' created successfully"
elif echo "$R2_OUTPUT" | grep -q "already exists"; then
  print_warn "R2 bucket 'nixos-module-docs' already exists"
else
  print_warn "R2 bucket creation status unknown: $R2_OUTPUT"
fi

# Create preview R2 Bucket
print_info "Creating R2 preview bucket..."
npx wrangler r2 bucket create nixos-module-docs-preview 2>&1 || true

# Update wrangler.jsonc with actual IDs
print_info "Updating wrangler.jsonc with resource IDs..."

CONFIG_FILE="wrangler.jsonc"
if [ -f "$CONFIG_FILE" ]; then
  # Create backup
  cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"

  # Update database_id
  if [ "$D1_ID" != "TODO_RUN_WRANGLER_D1_CREATE" ] && [ "$D1_ID" != "EXISTING_DB_ID" ]; then
    sed -i "s/\"database_id\": \"TODO_RUN_WRANGLER_D1_CREATE\"/\"database_id\": \"$D1_ID\"/" "$CONFIG_FILE"
    print_info "Updated D1 database ID"
  fi

  # Update KV namespace ID
  if [ "$KV_ID" != "TODO_RUN_WRANGLER_KV_CREATE" ]; then
    sed -i "s/\"id\": \"TODO_RUN_WRANGLER_KV_CREATE\"/\"id\": \"$KV_ID\"/" "$CONFIG_FILE"
    print_info "Updated KV namespace ID"
  fi

  # Update KV preview ID
  if [ "$KV_PREVIEW_ID" != "TODO_RUN_WRANGLER_KV_CREATE_PREVIEW" ]; then
    sed -i "s/\"preview_id\": \"TODO_RUN_WRANGLER_KV_CREATE_PREVIEW\"/\"preview_id\": \"$KV_PREVIEW_ID\"/" "$CONFIG_FILE" || true
  fi
fi

# Create API key secret
print_info "Setting up API key secret..."
if [ -n "${MODULE_API_KEY:-}" ]; then
  echo "$MODULE_API_KEY" | npx wrangler secret put API_KEY
  print_info "API key secret configured from SOPS"
else
  print_warn "Module API key not found; skipping API key configuration. Run 'npx wrangler secret put API_KEY' later."
fi

print_info "Setup complete! Summary:"
echo "----------------------------------------"
echo "D1 Database ID: $D1_ID"
echo "KV Namespace ID: $KV_ID"
echo "KV Preview ID: $KV_PREVIEW_ID"
echo "R2 Bucket: nixos-module-docs"
echo "----------------------------------------"

if [ "$D1_ID" = "TODO_RUN_WRANGLER_D1_CREATE" ] || [ "$KV_ID" = "TODO_RUN_WRANGLER_KV_CREATE" ]; then
  print_warn "Some resources need manual configuration. Please update wrangler.jsonc manually."
fi

print_info "Next steps:"
echo "1. Review wrangler.jsonc to ensure IDs are correct"
echo "2. Run database migrations: npm run db:migrate"
echo "3. Deploy to staging: npm run deploy:staging"
echo "4. Deploy to production: npm run deploy:production"
