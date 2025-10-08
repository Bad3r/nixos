# AI Search Setup and Testing

This document explains how to set up and test the AI Search integration for the NixOS Module Documentation API.

## Overview

The API uses **Cloudflare AI Search** (AutoRAG) to provide:
- 🔍 **Semantic Search**: Find modules by meaning, not just keywords
- 🤖 **AI-Powered Responses**: Get natural language answers about modules
- 🔀 **Hybrid Search**: Combine keyword and semantic search for best results

## Prerequisites

✅ AI Search index created in Cloudflare Dashboard
✅ Worker deployed with secrets configured
✅ MODULE_API_KEY available

## Setup Steps

### 1. Verify AI Search Index

Go to: `Cloudflare Dashboard → AI → AI Search`

Ensure you have an index with:
- **Name**: `nixos-modules-search-staging` (for staging)
- **Embedding Model**: `@cf/baai/bge-base-en-v1.5`
- **AI Gateway**: `nixos-modules-gateway-staging`
- **Data Source**: `nixos-modules-docs-staging` (D1 database)

### 2. Get API Key

The `MODULE_API_KEY` is stored in GitHub Secrets. You can either:

**A) Use existing key** (if you have it)

**B) Generate a new key:**
```bash
# Generate secure key
NEW_KEY=$(openssl rand -base64 32)
echo $NEW_KEY

# Update GitHub Secret
echo $NEW_KEY | gh secret set MODULE_API_KEY

# Update Worker secret (staging)
cd implementation/worker
echo $NEW_KEY | npx wrangler secret put API_KEY --env staging
```

### 3. Trigger Ingestion

Ingest the modules into AI Search:

```bash
cd implementation/worker

# Set the API key
export API_KEY='your-module-api-key'

# Run ingestion
./scripts/trigger-ingestion.sh
```

Expected output:
```
🔄 Triggering AI Search Ingestion
==================================

HTTP Status: 200

✅ Ingestion triggered successfully!

Response:
{
  "success": true,
  "processed": 10,
  "message": "AI Search ingestion completed successfully",
  ...
}

⏳ Waiting 15 seconds for ingestion to process...

✓ Ready to test!
```

### 4. Test AI Search

Run the comprehensive test script:

```bash
./scripts/test-ai-search.sh
```

Expected output:
```
🔍 Testing AI Search Integration
================================

1️⃣  Checking API health...
✓ API is healthy

2️⃣  Checking module stats...
✓ Found 10 modules

3️⃣  Testing keyword search...
✓ Keyword search working

4️⃣  Testing semantic search...
✓ AI Search is working!

5️⃣  Testing AI-powered search...
✓ AI-powered responses working!

📊 Summary
==========
Keyword Search: ✓
AI Search: ✓
AI Responses: ✓
```

## Testing Examples

### Keyword Search (Traditional)
```bash
curl "https://nixos-module-docs-api-staging.exploit.workers.dev/api/modules/search?q=networking&mode=keyword"
```

### Semantic Search (AI-powered)
```bash
curl "https://nixos-module-docs-api-staging.exploit.workers.dev/api/modules/search?q=web%20server%20configuration&mode=semantic"
```

### Hybrid Search (Default)
```bash
curl "https://nixos-module-docs-api-staging.exploit.workers.dev/api/modules/search?q=firewall"
```

### AI-Powered Responses
```bash
curl "https://nixos-module-docs-api-staging.exploit.workers.dev/api/modules/search?q=how%20to%20configure%20ssh&ai=true"
```

### With Custom Model
```bash
curl "https://nixos-module-docs-api-staging.exploit.workers.dev/api/modules/search?q=docker%20setup&ai=true&model=@cf/meta/llama-3.1-8b-instruct"
```

## API Parameters

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `q` | string | Search query (min 2 chars) | Required |
| `mode` | enum | `keyword`, `semantic`, `hybrid`, `ai` | `hybrid` |
| `ai` | boolean | Enable AI-powered responses | `false` |
| `model` | string | Override default LLM | `@cf/meta/llama-3.3-70b-instruct-fp8-fast` |
| `limit` | number | Results per page (1-50) | `20` |
| `offset` | number | Pagination offset | `0` |

## Response Structure

### Semantic/Hybrid Search Response
```json
{
  "query": "networking",
  "mode": "hybrid",
  "search_version": "ai-search",
  "results": [
    {
      "path": "services.networking",
      "name": "networking",
      "namespace": "services",
      "description": "Network configuration module",
      "snippet": "Configuration for <mark>networking</mark> services",
      "score": 0.95
    }
  ],
  "count": 5,
  "pagination": {
    "total": 5,
    "limit": 20,
    "offset": 0,
    "hasMore": false
  },
  "timestamp": "2025-10-08T15:00:00.000Z"
}
```

### AI-Powered Response
```json
{
  "query": "how to configure ssh",
  "mode": "ai",
  "aiResponse": "To configure SSH in NixOS, you need to enable the services.openssh module...",
  "queryRewritten": "ssh configuration setup",
  "results": [
    {
      "path": "services.openssh",
      ...
    }
  ],
  "count": 3
}
```

## Troubleshooting

### AI Search Returns No Results

**Problem**: Search falls back to keyword mode

**Solutions**:
1. Check if AI Search index exists in dashboard
2. Verify modules have been ingested: run `./scripts/trigger-ingestion.sh`
3. Wait 15-30 seconds after ingestion for processing

### Ingestion Fails with 401 Unauthorized

**Problem**: API_KEY is incorrect or not set

**Solutions**:
1. Verify `API_KEY` environment variable is set
2. Check that Worker secret is configured: `npx wrangler secret list --env staging`
3. Regenerate and update the key if needed

### AI Responses Not Generated

**Problem**: `aiResponse` is null in response

**Solutions**:
1. Ensure `ai=true` parameter is set or `mode=ai`
2. Check AI Gateway is configured and authenticated
3. Verify AI_GATEWAY_TOKEN secret is set in Worker

## Architecture

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │ HTTP Request
       ↓
┌─────────────────────────────────┐
│  Cloudflare Worker              │
│  ┌─────────────────────────┐   │
│  │  Search Handler         │   │
│  │  - Routes by mode       │   │
│  │  - Validates params     │   │
│  └───────────┬─────────────┘   │
│              ↓                  │
│  ┌─────────────────────────┐   │
│  │  AI Search Service      │   │
│  │  - Prepares documents   │   │
│  │  - Performs search      │   │
│  │  - Generates responses  │   │
│  └───────────┬─────────────┘   │
└──────────────┼─────────────────┘
               ↓
       ┌───────────────┐
       │  AI Search    │
       │  - Embeddings │
       │  - Retrieval  │
       │  - Ranking    │
       └───────┬───────┘
               ↓
       ┌───────────────┐
       │  AI Gateway   │
       │  - Caching    │
       │  - Fallback   │
       │  - Auth       │
       └───────┬───────┘
               ↓
       ┌───────────────┐
       │  Workers AI   │
       │  - LLM        │
       │  - Generation │
       └───────────────┘
```

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `trigger-ingestion.sh` | Manually trigger AI Search ingestion |
| `test-ai-search.sh` | Comprehensive AI Search testing |
| `set-ai-gateway-secret.sh` | Set AI Gateway token from SOPS |

## Configuration Files

| File | Purpose |
|------|---------|
| `wrangler.jsonc` | Worker configuration, bindings |
| `src/services/ai-search.ts` | AI Search service implementation |
| `src/api/handlers/modules/search.ts` | Search handler with mode routing |
| `secrets/ai-gateway.yaml` | SOPS-encrypted AI Gateway token |

## Further Reading

- [Cloudflare AI Search Documentation](https://developers.cloudflare.com/workers-ai/ai-search/)
- [Workers AI Models](https://developers.cloudflare.com/workers-ai/models/)
- [AI Gateway](https://developers.cloudflare.com/ai-gateway/)
