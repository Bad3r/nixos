#!/usr/bin/env bash

# Script to test AI Search functionality
set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ACCOUNT_SECRET_FILE="$REPO_ROOT/secrets/cf-acc-id.yaml"
TOKEN_SECRET_FILE="$REPO_ROOT/secrets/cf-api-token.yaml"

load_cloudflare_account_id() {
  if [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
    return
  fi

  if [ ! -f "$ACCOUNT_SECRET_FILE" ]; then
    echo -e "${YELLOW}⚠️  Cloudflare account ID secret not found at $ACCOUNT_SECRET_FILE${NC}" >&2
    return
  fi

  if ! command -v sops &>/dev/null; then
    echo -e "${YELLOW}⚠️  sops not installed; cannot decrypt Cloudflare account ID${NC}" >&2
    return
  fi

  if account_id=$(sops -d --extract '["cloudflare_account_id"]' "$ACCOUNT_SECRET_FILE" 2>/dev/null); then
    account_id=$(echo "$account_id" | tr -d '\n\r')
    if [ -n "$account_id" ]; then
      export CLOUDFLARE_ACCOUNT_ID="$account_id"
      echo -e "${GREEN}Loaded Cloudflare account ID from SOPS secrets${NC}"
    else
      echo -e "${YELLOW}⚠️  Cloudflare account ID secret is empty${NC}" >&2
    fi
  else
    echo -e "${YELLOW}⚠️  Failed to decrypt Cloudflare account ID from $ACCOUNT_SECRET_FILE${NC}" >&2
  fi
}

load_cloudflare_api_token() {
  if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
    if [ -z "${CF_API_TOKEN:-}" ]; then
      export CF_API_TOKEN="$CLOUDFLARE_API_TOKEN"
    fi
    return
  fi

  if [ ! -f "$TOKEN_SECRET_FILE" ]; then
    echo -e "${YELLOW}⚠️  Cloudflare API token secret not found at $TOKEN_SECRET_FILE${NC}" >&2
    return
  fi

  if ! command -v sops &>/dev/null; then
    echo -e "${YELLOW}⚠️  sops not installed; cannot decrypt Cloudflare API token${NC}" >&2
    return
  fi

  if token_value=$(sops -d --extract '["cf_api_token"]' "$TOKEN_SECRET_FILE" 2>/dev/null); then
    token_value=$(echo "$token_value" | tr -d '\n\r')
    if [ -n "$token_value" ]; then
      export CLOUDFLARE_API_TOKEN="$token_value"
      export CF_API_TOKEN="$token_value"
      echo -e "${GREEN}Loaded Cloudflare API token from SOPS secrets${NC}"
    else
      echo -e "${YELLOW}⚠️  Cloudflare API token secret is empty${NC}" >&2
    fi
  else
    echo -e "${YELLOW}⚠️  Failed to decrypt Cloudflare API token from $TOKEN_SECRET_FILE${NC}" >&2
  fi
}

load_cloudflare_account_id
load_cloudflare_api_token

WORKER_URL="${WORKER_URL:-https://nixos-module-docs-api-staging.exploit.workers.dev}"

echo "🔍 Testing AI Search Integration"
echo "================================"
echo ""

# Test 1: Check API health
echo "1️⃣  Checking API health..."
if curl -sf "$WORKER_URL/health" >/dev/null; then
  echo -e "${GREEN}✓ API is healthy${NC}"
else
  echo -e "${RED}✗ API is down${NC}"
  exit 1
fi
echo ""

# Test 2: Check stats
echo "2️⃣  Checking module stats..."
STATS=$(curl -s "$WORKER_URL/api/stats")
TOTAL_MODULES=$(echo "$STATS" | jq -r '.stats.total_modules')
echo -e "${GREEN}✓ Found $TOTAL_MODULES modules${NC}"
echo ""

# Test 3: Try keyword search (should always work)
echo "3️⃣  Testing keyword search..."
KEYWORD_RESULT=$(curl -s "$WORKER_URL/api/modules/search?q=system&mode=keyword")
KEYWORD_MODE=$(echo "$KEYWORD_RESULT" | jq -r '.mode')
KEYWORD_COUNT=$(echo "$KEYWORD_RESULT" | jq -r '.count')
KEYWORD_VERSION=$(echo "$KEYWORD_RESULT" | jq -r '.search_version // "unknown"')
echo "   Mode: $KEYWORD_MODE"
echo "   Version: $KEYWORD_VERSION"
echo "   Results: $KEYWORD_COUNT"
if [ "$KEYWORD_MODE" = "keyword" ]; then
  echo -e "${GREEN}✓ Keyword search working${NC}"
else
  echo -e "${RED}✗ Keyword search failed${NC}"
fi
echo ""

# Test 4: Try semantic search
echo "4️⃣  Testing semantic search..."
SEMANTIC_RESULT=$(curl -s "$WORKER_URL/api/modules/search?q=system&mode=semantic")
SEMANTIC_MODE=$(echo "$SEMANTIC_RESULT" | jq -r '.mode')
SEMANTIC_VERSION=$(echo "$SEMANTIC_RESULT" | jq -r '.search_version // "unknown"')
SEMANTIC_COUNT=$(echo "$SEMANTIC_RESULT" | jq -r '.count')
echo "   Mode: $SEMANTIC_MODE"
echo "   Version: $SEMANTIC_VERSION"
echo "   Results: $SEMANTIC_COUNT"
if [ "$SEMANTIC_VERSION" = "ai-search" ] || [ "$SEMANTIC_MODE" = "semantic" ]; then
  echo -e "${GREEN}✓ AI Search is working!${NC}"
else
  echo -e "${YELLOW}⚠ AI Search not available - falling back to keyword search${NC}"
  echo ""
  echo "📋 To enable AI Search:"
  echo "   1. Go to Cloudflare Dashboard → AI → AI Search"
  echo "   2. Create a new index named: nixos-modules-search-staging"
  echo "   3. Re-run this test"
fi
echo ""

# Test 5: Try AI mode
echo "5️⃣  Testing AI-powered search..."
AI_RESULT=$(curl -s "$WORKER_URL/api/modules/search?q=how%20to%20configure%20networking&ai=true")
AI_MODE=$(echo "$AI_RESULT" | jq -r '.mode')
AI_RESPONSE=$(echo "$AI_RESULT" | jq -r '.aiResponse // "none"')
echo "   Mode: $AI_MODE"
if [ "$AI_RESPONSE" != "none" ] && [ "$AI_RESPONSE" != "null" ]; then
  echo -e "${GREEN}✓ AI-powered responses working!${NC}"
  echo "   Response preview: $(echo "$AI_RESPONSE" | cut -c1-100)..."
else
  echo -e "${YELLOW}⚠ AI-powered responses not available${NC}"
  echo "   This requires AI Search to be configured"
fi
echo ""

# Optional: verify Cloudflare AI Search indexes when authenticated
if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
  echo "6️⃣  Verifying AI Search indexes via Cloudflare API..."
  if [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
    echo -e "${YELLOW}⚠️  Cloudflare account ID unavailable; skipping API verification${NC}"
  else
    RESPONSE_FILE=$(mktemp)
    HTTP_STATUS=$(curl -s -w "%{http_code}" -o "$RESPONSE_FILE" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/ai/ai-search/indexes")

    if [ "$HTTP_STATUS" = "200" ]; then
      INDEX_COUNT="unknown"
      if command -v jq &>/dev/null; then
        INDEX_COUNT=$(jq -r '.result | length' "$RESPONSE_FILE")
        INDEX_NAMES=$(jq -r '.result[].name' "$RESPONSE_FILE" 2>/dev/null || echo "")
      fi
      echo -e "${GREEN}✓ Cloudflare API responded with $INDEX_COUNT index(es)${NC}"
      if [ -n "${INDEX_NAMES:-}" ]; then
        echo "   Indexes:"
        while IFS= read -r index_name; do
          printf '     • %s\n' "$index_name"
        done <<<"$INDEX_NAMES"
      fi
    else
      echo -e "${YELLOW}⚠️  Failed to list AI Search indexes (HTTP $HTTP_STATUS)${NC}"
      if [ -s "$RESPONSE_FILE" ]; then
        echo "   Response: $(cat "$RESPONSE_FILE")"
      fi
    fi
    rm -f "$RESPONSE_FILE"
  fi
  echo ""
else
  echo "6️⃣  (Skipped) Cloudflare API token not available"
  echo ""
fi

# Summary
echo "📊 Summary"
echo "=========="
echo "Keyword Search: ${GREEN}✓${NC}"
if [ "$SEMANTIC_VERSION" = "ai-search" ]; then
  echo "AI Search: ${GREEN}✓${NC}"
  echo "AI Responses: ${GREEN}✓${NC}"
else
  echo "AI Search: ${YELLOW}Not configured${NC}"
  echo "AI Responses: ${YELLOW}Not available${NC}"
fi
echo ""

# Instructions if AI Search not available
if [ "$SEMANTIC_VERSION" != "ai-search" ]; then
  echo "⚙️  Setup Instructions"
  echo "===================="
  echo ""
  echo "AI Search is not configured. To enable it:"
  echo ""
  echo "1. Create AI Search Index:"
  echo "   → Go to: https://dash.cloudflare.com/[YOUR_ACCOUNT_ID]/ai/ai-search"
  echo "   → Click 'Create Index'"
  echo "   → Name: nixos-modules-search-staging"
  echo "   → Embedding Model: @cf/baai/bge-base-en-v1.5"
  echo ""
  echo "2. Ingest modules (requires API_KEY):"
  if [ -n "${API_KEY:-}" ]; then
    echo "   curl -X POST \"$WORKER_URL/api/admin/ai-search/ingest\" \\"
    echo '        -H "X-API-Key: $API_KEY"'
  else
    echo "   export API_KEY='your-api-key-from-github-secrets'"
    echo "   curl -X POST \"$WORKER_URL/api/admin/ai-search/ingest\" \\"
    echo '        -H "X-API-Key: $API_KEY"'
  fi
  echo ""
  echo "3. Test again:"
  echo "   $0"
  echo ""
fi
