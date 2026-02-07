# Cloudflare Containers Technical Documentation

> **Status**: Beta
> **Last Updated**: February 2026
> **Minimum Requirement**: Workers Paid Plan ($5/month)

## Overview

Cloudflare Containers is a serverless container platform that extends Workers by allowing you to run **any language/runtime** in Docker containers on Cloudflare's global network. Containers are backed by **Durable Objects**, giving each instance a globally addressable identity, persistent state capabilities, and lifecycle hooks.

## Key Features

- **Any Language**: Run Python, Go, Rust, PHP, Ruby, or any Docker-compatible runtime
- **Global Distribution**: Images distributed to Cloudflare's edge network
- **Durable Object Integration**: Each container has state, identity, and lifecycle hooks
- **On-Demand Scaling**: Containers spin up when needed, sleep when idle
- **VM Isolation**: Strong security isolation (not just namespaces)

## Documentation Index

| Document                                        | Description                                         |
| ----------------------------------------------- | --------------------------------------------------- |
| [Architecture](./architecture.md)               | Core design, request flow, and system components    |
| [Configuration](./configuration.md)             | Wrangler setup, Dockerfile requirements, deployment |
| [API Reference](./api-reference.md)             | Container Package methods, properties, and helpers  |
| [Lifecycle Management](./lifecycle.md)          | Container states, cold starts, shutdown behavior    |
| [Storage & Networking](./storage-networking.md) | Disk, R2 FUSE, ingress/egress, WebSockets           |
| [Use Cases & Examples](./use-cases.md)          | Practical examples and patterns                     |
| [Limits & Roadmap](./limitations-roadmap.md)    | Beta constraints and planned features               |

## Quick Start

### 1. Create a Project

```bash
npm create cloudflare@latest my-container-app -- --template container
```

### 2. Ensure Docker is Running

```bash
docker info
```

### 3. Deploy

```bash
npx wrangler deploy
```

## Instance Types

| Type         | vCPU | Memory  | Disk  |
| ------------ | ---- | ------- | ----- |
| `lite`       | 1/16 | 256 MiB | 2 GB  |
| `basic`      | 1/4  | 1 GiB   | 4 GB  |
| `standard-1` | 1/2  | 4 GiB   | 8 GB  |
| `standard-2` | 1    | 6 GiB   | 12 GB |
| `standard-3` | 2    | 8 GiB   | 16 GB |

## When to Use Containers vs Workers

| Aspect         | Workers         | Containers                 |
| -------------- | --------------- | -------------------------- |
| **Cold Start** | ~0ms            | 2-3 seconds                |
| **Runtime**    | V8 (JS/TS/WASM) | Any (Docker)               |
| **Memory**     | 128 MB          | Up to 8 GB                 |
| **CPU Time**   | 30s (paid)      | Unlimited                  |
| **Disk**       | None            | 2-16 GB                    |
| **Best For**   | API, edge logic | Heavy compute, legacy apps |

## Minimal Example

```typescript
// src/index.ts
import { Container, getContainer } from "@cloudflare/containers";

export class Backend extends Container {
  defaultPort = 8080;
  sleepAfter = "5m";
}

export default {
  async fetch(request: Request, env: Env) {
    const backend = getContainer(env.BACKEND, "main");
    return backend.fetch(request);
  },
};
```

```dockerfile
# Dockerfile
FROM node:20-alpine
WORKDIR /app
COPY . .
RUN npm install
EXPOSE 8080
CMD ["node", "server.js"]
```

## Official Resources

- [Cloudflare Containers Documentation](https://developers.cloudflare.com/containers/)
- [Container Package (npm)](https://www.npmjs.com/package/@cloudflare/containers)
- [Container Package (GitHub)](https://github.com/cloudflare/containers)
- [Example Demos](https://github.com/cloudflare/containers-demos)
