#!/usr/bin/env bash

# Script to trigger AI Search ingestion
set -euo pipefail

WORKER_URL="${WORKER_URL:-https://nixos-module-docs-api-staging.exploit.workers.dev}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔄 Triggering AI Search Ingestion"
echo "=================================="
echo ""

# Check if API_KEY is provided
if [ -z "${API_KEY:-}" ]; then
    echo -e "${RED}❌ Error: API_KEY environment variable not set${NC}"
    echo ""
    echo "Please provide the MODULE_API_KEY from GitHub Secrets:"
    echo "  export API_KEY='your-api-key-here'"
    echo ""
    echo "You can find it in GitHub Secrets as MODULE_API_KEY"
    echo "To generate a new one: openssl rand -base64 32"
    exit 1
fi

echo -e "${YELLOW}Triggering ingestion at: $WORKER_URL${NC}"
echo ""

# Trigger ingestion
RESPONSE=$(curl -X POST "$WORKER_URL/api/admin/ai-search/ingest" \
    -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    -w "\n%{http_code}" \
    -s)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

echo "HTTP Status: $HTTP_CODE"
echo ""

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    echo -e "${GREEN}✅ Ingestion triggered successfully!${NC}"
    echo ""
    echo "Response:"
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    echo ""
    echo -e "${YELLOW}⏳ Waiting 15 seconds for ingestion to process...${NC}"
    sleep 15
    echo ""
    echo -e "${GREEN}✓ Ready to test!${NC}"
    echo ""
    echo "Run the test script to verify:"
    echo "  ./scripts/test-ai-search.sh"
else
    echo -e "${RED}❌ Ingestion failed with status $HTTP_CODE${NC}"
    echo ""
    echo "Response:"
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    exit 1
fi
