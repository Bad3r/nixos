#!/usr/bin/env bash

# Script to decrypt AI Gateway token from SOPS and set it as a Wrangler secret
# This script should be run after setting up SOPS with proper age keys

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Setting AI Gateway authentication token...${NC}"

# Check if sops is available
if ! command -v sops &>/dev/null; then
  echo -e "${RED}Error: sops is not installed${NC}"
  echo "Please install sops: https://github.com/getsops/sops"
  exit 1
fi

# Check if wrangler is available
if ! command -v wrangler &>/dev/null && ! command -v npx &>/dev/null; then
  echo -e "${RED}Error: wrangler is not installed${NC}"
  echo "Please install wrangler: npm install -g wrangler"
  exit 1
fi

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SECRETS_FILE="$REPO_ROOT/secrets/cf-ai-gateway.yaml"
ACCOUNT_SECRET_FILE="$REPO_ROOT/secrets/cf-acc-id.yaml"
API_SECRET_FILE="$REPO_ROOT/secrets/cf-api-token.yaml"

# Load Cloudflare account ID from SOPS if not already set
if [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
  if [ -f "$ACCOUNT_SECRET_FILE" ]; then
    if account_id=$(sops -d --extract '["cloudflare_account_id"]' "$ACCOUNT_SECRET_FILE" 2>/dev/null); then
      account_id=$(echo "$account_id" | tr -d '\n\r')
      if [ -n "$account_id" ]; then
        export CLOUDFLARE_ACCOUNT_ID="$account_id"
        echo -e "${GREEN}Loaded Cloudflare account ID from SOPS secrets${NC}"
      else
        echo -e "${YELLOW}Warning: Cloudflare account ID secret is empty${NC}"
      fi
    else
      echo -e "${YELLOW}Warning: Failed to decrypt Cloudflare account ID from $ACCOUNT_SECRET_FILE${NC}"
    fi
  else
    echo -e "${YELLOW}Warning: Cloudflare account ID secret file not found at $ACCOUNT_SECRET_FILE${NC}"
  fi
fi

# Load Cloudflare API token from SOPS if not already set
if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  if [ -f "$API_SECRET_FILE" ]; then
    if token_value=$(sops -d --extract '["cf_api_token"]' "$API_SECRET_FILE" 2>/dev/null); then
      token_value=$(echo "$token_value" | tr -d '\n\r')
      if [ -n "$token_value" ]; then
        export CLOUDFLARE_API_TOKEN="$token_value"
        export CF_API_TOKEN="$token_value"
        echo -e "${GREEN}Loaded Cloudflare API token from SOPS secrets${NC}"
      else
        echo -e "${YELLOW}Warning: Cloudflare API token secret is empty${NC}"
      fi
    else
      echo -e "${YELLOW}Warning: Failed to decrypt Cloudflare API token from $API_SECRET_FILE${NC}"
    fi
  else
    echo -e "${YELLOW}Warning: Cloudflare API token secret file not found at $API_SECRET_FILE${NC}"
  fi
fi

# Ensure CF_API_TOKEN mirrors CLOUDFLARE_API_TOKEN when available
if [ -n "${CLOUDFLARE_API_TOKEN:-}" ] && [ -z "${CF_API_TOKEN:-}" ]; then
  export CF_API_TOKEN="$CLOUDFLARE_API_TOKEN"
fi

# Check if secrets file exists
if [ ! -f "$SECRETS_FILE" ]; then
  echo -e "${RED}Error: Secrets file not found: $SECRETS_FILE${NC}"
  exit 1
fi

# Decrypt the token
echo "Decrypting AI Gateway token from SOPS..."
TOKEN=$(sops -d "$SECRETS_FILE" | grep "^ai_gateway_token:" | cut -d' ' -f2)
TOKEN_STAGING=$(sops -d "$SECRETS_FILE" | grep "^ai_gateway_token_staging:" | cut -d' ' -f2)

if [ -z "$TOKEN" ]; then
  echo -e "${RED}Error: Failed to decrypt token${NC}"
  exit 1
fi

# Function to run wrangler command
run_wrangler() {
  if command -v wrangler &>/dev/null; then
    wrangler "$@"
  else
    npx wrangler "$@"
  fi
}

# Set the secret for production
echo -e "\n${YELLOW}Setting production secret...${NC}"
echo "$TOKEN" | run_wrangler secret put AI_GATEWAY_TOKEN

# Set the secret for staging
if [ -n "$TOKEN_STAGING" ]; then
  echo -e "\n${YELLOW}Setting staging secret...${NC}"
  echo "$TOKEN_STAGING" | run_wrangler secret put AI_GATEWAY_TOKEN --env staging
fi

echo -e "\n${GREEN}✓ AI Gateway token has been set successfully!${NC}"
echo -e "${YELLOW}Note: You may need to redeploy your Worker for the changes to take effect.${NC}"
