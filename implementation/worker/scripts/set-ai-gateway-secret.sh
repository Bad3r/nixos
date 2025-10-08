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
if ! command -v sops &> /dev/null; then
    echo -e "${RED}Error: sops is not installed${NC}"
    echo "Please install sops: https://github.com/getsops/sops"
    exit 1
fi

# Check if wrangler is available
if ! command -v wrangler &> /dev/null && ! command -v npx &> /dev/null; then
    echo -e "${RED}Error: wrangler is not installed${NC}"
    echo "Please install wrangler: npm install -g wrangler"
    exit 1
fi

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKER_DIR="$(dirname "$SCRIPT_DIR")"
SECRETS_FILE="$WORKER_DIR/secrets/ai-gateway.yaml"

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
    if command -v wrangler &> /dev/null; then
        wrangler "$@"
    else
        npx wrangler "$@"
    fi
}

# Set the secret for production
echo -e "\n${YELLOW}Setting production secret...${NC}"
echo "$TOKEN" | run_wrangler secret put AI_GATEWAY_TOKEN

# Set the secret for staging
if [ ! -z "$TOKEN_STAGING" ]; then
    echo -e "\n${YELLOW}Setting staging secret...${NC}"
    echo "$TOKEN_STAGING" | run_wrangler secret put AI_GATEWAY_TOKEN --env staging
fi

echo -e "\n${GREEN}✓ AI Gateway token has been set successfully!${NC}"
echo -e "${YELLOW}Note: You may need to redeploy your Worker for the changes to take effect.${NC}"