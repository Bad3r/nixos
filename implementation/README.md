# NixOS Module Documentation API - Implementation

A simplified, production-ready API for documenting and searching NixOS modules using Cloudflare Workers, D1 Database, and KV caching.

## 🎯 Project Status

**Current Phase**: MVP Development
**Completion**: 40% (Core API complete, Frontend/Extraction pending)
**Estimated Completion**: 3-4 weeks

## 🏗️ Architecture (Simplified)

```
┌─────────────┐     ┌──────────────┐     ┌────────────┐
│   GitHub    │────▶│   Worker     │────▶│     D1     │
│   Actions   │     │   (Hono)     │     │  Database  │
└─────────────┘     └──────────────┘     └────────────┘
                            │                    │
                            ▼                    │
                    ┌──────────────┐            │
                    │  KV Cache    │◀───────────┘
                    └──────────────┘
                            │
                            ▼
                    ┌──────────────┐
                    │ R2 Storage   │
                    │  (Optional)  │
                    └──────────────┘
```

## 📁 Project Structure

```
implementation/
├── worker/                    # Main Worker application
│   ├── src/
│   │   ├── index.ts          # Main entry point ✅
│   │   ├── types.ts          # TypeScript definitions ✅
│   │   └── api/
│   │       └── handlers/     # API endpoint handlers ✅
│   ├── migrations/           # Database migrations ✅
│   ├── scripts/              # Setup and utility scripts ✅
│   ├── wrangler.jsonc        # Cloudflare configuration ✅
│   └── package.json          # Dependencies ✅
├── frontend/                 # Web UI (pending)
├── nix/                      # Module extraction (pending)
└── tests/                    # Test suite (pending)
```

## 🚀 Quick Start

### Prerequisites

- Node.js 18+
- Cloudflare account
- Wrangler CLI (`npm install -g wrangler`)

### Setup

```bash
# Clone and navigate to implementation
cd /home/vx/nixos/implementation/worker

# Install dependencies
npm install

# Login to Cloudflare
npx wrangler login

# Run setup script to create resources
bash scripts/setup.sh

# Apply database migrations
npm run db:migrate:local

# Start development server
npm run dev
```

### Test API Endpoints

```bash
# Health check
curl http://localhost:8787/health

# List modules
curl http://localhost:8787/api/modules

# Search modules
curl "http://localhost:8787/api/modules/search?q=git"

# Get specific module
curl http://localhost:8787/api/modules/apps/git

# Get statistics
curl http://localhost:8787/api/stats
```

## 📚 API Documentation

### Public Endpoints (No Auth)

| Method | Endpoint                        | Description         |
| ------ | ------------------------------- | ------------------- |
| GET    | `/health`                       | Health check        |
| GET    | `/api/modules`                  | List all modules    |
| GET    | `/api/modules/:namespace/:name` | Get specific module |
| GET    | `/api/modules/search`           | Search modules      |
| GET    | `/api/stats`                    | Global statistics   |

### Protected Endpoints (API Key Required)

| Method | Endpoint             | Description          |
| ------ | -------------------- | -------------------- |
| POST   | `/api/modules/batch` | Batch update modules |

### Query Parameters

**List Modules**

- `namespace`: Filter by namespace
- `limit`: Results per page (1-100, default: 50)
- `offset`: Pagination offset
- `sort`: Sort by name/namespace/usage/updated

**Search Modules**

- `q`: Search query (min 2 chars)
- `limit`: Results per page (1-50, default: 20)
- `offset`: Pagination offset

## 🔧 Configuration

### Environment Variables

```bash
# wrangler.jsonc vars
ENVIRONMENT=development
CACHE_TTL=300
MAX_BATCH_SIZE=50
ENABLE_DEBUG=true
API_VERSION=v1

# Secrets (set with wrangler secret put)
API_KEY=your-secret-api-key
```

### Cloudflare Resources

Run `scripts/setup.sh` to create:

- D1 Database: `nixos-modules-db`
- KV Namespace: `MODULE_CACHE`
- R2 Bucket: `nixos-module-docs`

## 🗃️ Database Schema

```sql
-- Core tables
modules                 -- Module metadata
module_options         -- Configuration options
module_dependencies    -- Import relationships
host_usage            -- Usage tracking

-- Search
modules_fts           -- Full-text search index

-- Views
modules_with_usage    -- Modules with usage counts
namespace_stats       -- Namespace statistics
```

## 🚢 Deployment

### Staging

```bash
npm run deploy:staging
```

### Production

```bash
npm run deploy:production
```

## 📊 Performance

- **Response Time**: < 50ms (cached), < 200ms (uncached)
- **Cache Hit Rate**: Target 80%+
- **Database Size**: < 10MB for 1000+ modules
- **Monthly Cost**: < $1 (free tier)

## 🧪 Testing

```bash
# Run tests (when implemented)
npm test

# Coverage report
npm run test:coverage

# E2E tests
npm run test:e2e
```

## 🔄 CI/CD Integration

```yaml
# .github/workflows/update-modules.yml
on:
  push:
    paths:
      - "modules/**"

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: nix run .#module-docs-exporter -- --format json --out .cache/module-docs
      - run: |
          curl -X POST https://api.nixos-modules.workers.dev/api/modules/batch \
            -H "X-API-Key: ${{ secrets.API_KEY }}" \
            -d @.cache/module-docs/json/modules.json
```

## 🐛 Troubleshooting

### Common Issues

1. **"TODO_RUN_WRANGLER_D1_CREATE" errors**
   - Run `scripts/setup.sh` to create resources
   - Update `wrangler.jsonc` with actual IDs

2. **Database migration failures**
   - Check D1 database exists: `npx wrangler d1 list`
   - Try local migrations first: `npm run db:migrate:local`

3. **API returns 404**
   - Ensure you're using `/api/` prefix
   - Check route definitions in `src/index.ts`

4. **Cache not working**
   - Verify KV namespace is created
   - Check KV binding in `wrangler.jsonc`

## 📈 Monitoring

- **Health Endpoint**: `/health`
- **Metrics**: Available at `/api/stats`
- **Logs**: `npx wrangler tail` (production)
- **Analytics**: Cloudflare dashboard

## 🤝 Contributing

1. Follow the dendritic pattern for modules
2. Run formatter: `npm run format`
3. Add tests for new features
4. Update migrations for schema changes
5. Document API changes

## 📝 License

MIT

## 🔗 Links

- [Cloudflare Workers Docs](https://developers.cloudflare.com/workers/)
- [D1 Database Docs](https://developers.cloudflare.com/d1/)
- [Hono Framework](https://hono.dev/)
- [NixOS Module System](https://nixos.org/manual/nixos/stable/#sec-writing-modules)

---

**Implementation by**: vx
**Assisted by**: Claude Code
**Last Updated**: 2025-10-08
