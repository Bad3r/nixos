# Cloudflare Containers Configuration

## Prerequisites

### Docker Requirement

Docker must be running locally for image builds:

```bash
# Verify Docker is running
docker info

# If not running, start Docker Desktop or:
sudo systemctl start docker
```

### Workers Paid Plan

Containers require the Workers Paid plan ($5/month minimum).

## Project Setup

### Create New Project

```bash
# Using template
npm create cloudflare@latest my-container-app -- --template container

# Or manually
mkdir my-container-app && cd my-container-app
npm init -y
npm install @cloudflare/containers wrangler
```

### Install Container Package

```bash
# npm
npm install @cloudflare/containers

# yarn
yarn add @cloudflare/containers

# pnpm
pnpm add @cloudflare/containers
```

## Wrangler Configuration

### Complete Example (wrangler.jsonc)

```jsonc
{
  "name": "my-container-app",
  "main": "src/index.ts",
  "compatibility_date": "2026-02-04",
  "compatibility_flags": ["nodejs_compat"],

  // Container definition
  "containers": [
    {
      "class_name": "MyContainer",
      "image": "./Dockerfile",
      "instance_type": "standard-1",
      "max_instances": 10,
      "rollout_step_percentage": 10,
      "rollout_active_grace_period": 300,
    },
  ],

  // Durable Object binding (required)
  "durable_objects": {
    "bindings": [
      {
        "class_name": "MyContainer",
        "name": "MY_CONTAINER",
      },
    ],
  },

  // Migration (required for new DO classes)
  "migrations": [
    {
      "new_sqlite_classes": ["MyContainer"],
      "tag": "v1",
    },
  ],

  // Optional: Environment variables
  "vars": {
    "ENVIRONMENT": "production",
  },

  // Optional: Cron triggers
  "triggers": {
    "crons": ["0 * * * *"],
  },
}
```

### TOML Format (wrangler.toml)

```toml
name = "my-container-app"
main = "src/index.ts"
compatibility_date = "2026-02-04"
compatibility_flags = ["nodejs_compat"]

[[containers]]
class_name = "MyContainer"
image = "./Dockerfile"
instance_type = "standard-1"
max_instances = 10
rollout_step_percentage = 10
rollout_active_grace_period = 300

[[durable_objects.bindings]]
class_name = "MyContainer"
name = "MY_CONTAINER"

[[migrations]]
new_sqlite_classes = ["MyContainer"]
tag = "v1"

[vars]
ENVIRONMENT = "production"

[triggers]
crons = ["0 * * * *"]
```

## Container Configuration Options

| Option                        | Type   | Required | Description                                          |
| ----------------------------- | ------ | -------- | ---------------------------------------------------- |
| `class_name`                  | string | Yes      | Name of the Container class in your code             |
| `image`                       | string | Yes      | Dockerfile path or registry URL                      |
| `instance_type`               | string | No       | `lite`, `basic`, `standard-1/2/3` (default: `basic`) |
| `max_instances`               | number | No       | Maximum concurrent instances                         |
| `rollout_step_percentage`     | number | No       | First rollout step percentage (default: 10)          |
| `rollout_active_grace_period` | number | No       | Seconds before active containers update              |

## Image Configuration

### Local Dockerfile

```jsonc
{
  "containers": [
    {
      "image": "./Dockerfile", // Relative path to Dockerfile
    },
  ],
}
```

### Cloudflare Registry

```jsonc
{
  "containers": [
    {
      "image": "registry.cloudflare.com/my-account/my-image:v1.0",
    },
  ],
}
```

### Amazon ECR

First, configure credentials:

```bash
npx wrangler containers registries configure \
  123456789012.dkr.ecr.us-east-1.amazonaws.com \
  --aws-access-key-id=AKIAIOSFODNN7EXAMPLE
```

Then use in config:

```jsonc
{
  "containers": [
    {
      "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-repo:tag",
    },
  ],
}
```

## Dockerfile Requirements

### Basic Example

```dockerfile
FROM node:20-alpine

WORKDIR /app

# Copy and install dependencies
COPY package*.json ./
RUN npm ci --only=production

# Copy application code
COPY . .

# Expose port (must match defaultPort in Container class)
EXPOSE 8080

# Start command
CMD ["node", "server.js"]
```

### Multi-Stage Build (Optimized)

```dockerfile
# Build stage
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Production stage
FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
EXPOSE 8080
CMD ["node", "dist/server.js"]
```

### Python Example

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080

CMD ["python", "app.py"]
```

### Go Example

```dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.* ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o server .

FROM alpine:3.19
COPY --from=builder /app/server /server
EXPOSE 8080
CMD ["/server"]
```

## Environment Variables

### Static Variables (wrangler.jsonc)

```jsonc
{
  "vars": {
    "LOG_LEVEL": "info",
    "API_URL": "https://api.example.com",
  },
}
```

### Secrets (CLI)

```bash
# Add secret
npx wrangler secret put API_KEY

# Delete secret
npx wrangler secret delete API_KEY

# List secrets
npx wrangler secret list
```

### Local Development (.dev.vars)

```bash
# .dev.vars (do not commit to git)
API_KEY=your-dev-api-key
DATABASE_URL=postgres://localhost/dev
```

### Passing to Container

```typescript
import { Container } from "@cloudflare/containers";

export class MyContainer extends Container {
  defaultPort = 8080;

  // Pass env vars to container process
  envVars = {
    LOG_LEVEL: this.env.LOG_LEVEL,
    API_KEY: this.env.API_KEY,
    CUSTOM_VAR: "hardcoded-value",
  };
}
```

## Deployment

### Standard Deploy

```bash
npx wrangler deploy
```

### Deploy with Secrets

```bash
# First, set secrets
npx wrangler secret put API_KEY
npx wrangler secret put DATABASE_URL

# Then deploy
npx wrangler deploy
```

### Image-Only Push

```bash
# Build and push image without deploying Worker
npx wrangler containers build -p -t my-image:v1.0 .

# Or push existing image
npx wrangler containers push my-image:v1.0
```

## Local Development

### Run Locally

```bash
npx wrangler dev
```

### Requirements for Local Dev

- Docker must be running
- Container builds locally
- Same behavior as production (mostly)

### Vite Plugin (Alternative)

```typescript
// vite.config.ts
import { defineConfig } from "vite";
import { cloudflare } from "@cloudflare/vite-plugin";

export default defineConfig({
  plugins: [cloudflare()],
});
```

**Note**: Vite plugin has limitations with registry URLs; use Dockerfile path instead.

## Wrangler Commands

### Container-Specific Commands

```bash
# Build container image
npx wrangler containers build -t my-image:tag .

# Build and push
npx wrangler containers build -p -t my-image:tag .

# Push existing image
npx wrangler containers push my-image:tag

# List images
npx wrangler containers images list

# Delete image
npx wrangler containers images delete my-image:tag

# Configure external registry
npx wrangler containers registries configure <registry-url>
```

### General Commands

```bash
# Deploy
npx wrangler deploy

# Local development
npx wrangler dev

# Tail logs
npx wrangler tail

# View deployments
npx wrangler deployments list
```

## TypeScript Configuration

### tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "lib": ["ES2022"],
    "types": ["@cloudflare/workers-types"],
    "strict": true,
    "noEmit": true
  },
  "include": ["src/**/*"]
}
```

### Type Definitions

```typescript
// src/types.ts
export interface Env {
  MY_CONTAINER: DurableObjectNamespace<MyContainer>;
  API_KEY: string;
  LOG_LEVEL: string;
}
```

## Project Structure

### Recommended Layout

```
my-container-app/
├── src/
│   ├── index.ts          # Worker entry point
│   ├── container.ts      # Container class definition
│   └── types.ts          # TypeScript types
├── container/
│   ├── Dockerfile        # Container image definition
│   ├── package.json      # Container dependencies
│   └── server.js         # Container application
├── wrangler.jsonc        # Wrangler configuration
├── package.json          # Worker dependencies
└── tsconfig.json         # TypeScript config
```
