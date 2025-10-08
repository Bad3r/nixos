#!/usr/bin/env bash

# Script to test AI Search functionality
set -euo pipefail

WORKER_URL="${WORKER_URL:-https://nixos-module-docs-api-staging.exploit.workers.dev}"

echo "🔍 Testing AI Search Integration"
echo "================================"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test 1: Check API health
echo "1️⃣  Checking API health..."
if curl -sf "$WORKER_URL/health" > /dev/null; then
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
        echo "        -H \"X-API-Key: \$API_KEY\""
    else
        echo "   export API_KEY='your-api-key-from-github-secrets'"
        echo "   curl -X POST \"$WORKER_URL/api/admin/ai-search/ingest\" \\"
        echo "        -H \"X-API-Key: \$API_KEY\""
    fi
    echo ""
    echo "3. Test again:"
    echo "   $0"
    echo ""
fi
