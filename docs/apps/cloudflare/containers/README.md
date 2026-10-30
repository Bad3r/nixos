# Cloudflare Containers

Cloudflare Containers runs Docker images on Cloudflare's network, driven from a Worker.
Each container instance is backed by a Durable Object, which gives it a globally addressable identity, persistent state, and lifecycle hooks.
Containers need the Workers Paid plan.

## Features

- **Any language**: Python, Go, Rust, PHP, Ruby, or any runtime packaged as a container image.
- **Global distribution**: images are pre-fetched to Cloudflare's edge locations.
- **Durable Object integration**: each container has state, identity, and lifecycle hooks.
- **On-demand scaling**: containers start when a request needs them and sleep when idle.
- **VM isolation**: each container runs in its own VM, not only in namespaces.

## Pages

| Page                                      | Covers                                  |
| ----------------------------------------- | --------------------------------------- |
| [Architecture](./architecture.md)         | Components, request flow, location      |
| [Images](./images.md)                     | Registries, distribution, Dockerfiles   |
| [Configuration](./configuration.md)       | Project setup, Wrangler, TypeScript     |
| [Deployment](./deployment.md)             | Variables, secrets, deploy, local dev   |
| [API reference](./api-reference.md)       | Container class and helper functions    |
| [API methods](./api-methods.md)           | Instance methods and `ctx.container`    |
| [API hooks](./api-hooks.md)               | Status hooks and a complete example     |
| [Lifecycle](./lifecycle.md)               | States, sleep, OOM, host maintenance    |
| [Cold starts](./cold-starts.md)           | Start latency and keep-warm patterns    |
| [Shutdown](./shutdown.md)                 | SIGTERM handling and rollouts           |
| [Storage](./storage.md)                   | Ephemeral disk and Durable Object state |
| [R2 mount](./r2-mount.md)                 | R2 buckets over FUSE                    |
| [Networking](./networking.md)             | Ingress, egress, DNS, isolation         |
| [Internal routing](./internal-routing.md) | Extra ports and container-to-container  |
| [Use cases](./use-cases.md)               | Workload fit and worked examples        |
| [Limitations](./limitations.md)           | Beta constraints and workarounds        |
| [Comparison](./comparison.md)             | Workers, Kubernetes, Lambda, Fly.io     |

## Quick start

Create a project from the container template:

```bash
npm create cloudflare@latest my-container-app -- --template container
```

Confirm Docker is running, then deploy:

```bash
docker info
npx wrangler deploy
```

## Instance types

| Type         | vCPU | Memory  | Disk  | Fits                  |
| ------------ | ---- | ------- | ----- | --------------------- |
| `lite`       | 1/16 | 256 MiB | 2 GB  | Scripts, lightweight  |
| `basic`      | 1/4  | 1 GiB   | 4 GB  | Typical web services  |
| `standard-1` | 1/2  | 4 GiB   | 8 GB  | Memory-intensive apps |
| `standard-2` | 1    | 6 GiB   | 12 GB | Large data processing |
| `standard-3` | 2    | 8 GiB   | 16 GB | Heavy workloads       |
| `standard-4` | 4    | 12 GiB  | 20 GB | Largest workloads     |

Custom instance types go up to 4 vCPU, 12 GiB memory, and 20 GB disk, with a minimum of 1 vCPU.
Resources are fixed per instance type, and a process that exceeds its memory is killed ([Lifecycle](./lifecycle.md#out-of-memory)).

## Nix build suitability

Containers fit Nix package builds poorly as the primary builder, especially kernel and browser-heavy closures, because of the per-instance resource limits and beta platform gaps.
The workable split:

1. Compile on dedicated x86_64 builders: local, VM, or remote builders.
2. Use Cloudflare R2 as the binary cache storage backend for Attic or a similar cache frontend.
3. Keep Workers and Containers for orchestration, APIs, and cache serving rather than full package compilation.

## Minimal example

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

## Official resources

- [Cloudflare Containers Documentation](https://developers.cloudflare.com/containers/)
- [Containers: Limits and Instance Types](https://developers.cloudflare.com/containers/platform-details/limits/)
- [Containers: Beta Info and Roadmap](https://developers.cloudflare.com/containers/beta-info/)
- [Containers: Pricing](https://developers.cloudflare.com/containers/pricing/)
- [Workers Builds: Limits and Pricing](https://developers.cloudflare.com/workers/ci-cd/builds/limits-and-pricing/)
- [Workers CPU time update (up to 5 minutes)](https://developers.cloudflare.com/changelog/2025-03-25-higher-cpu-limits/)
- [R2 Pricing](https://developers.cloudflare.com/r2/pricing/)
- [Container Package (npm)](https://www.npmjs.com/package/@cloudflare/containers)
- [Container Package (GitHub)](https://github.com/cloudflare/containers)
- [Example Demos](https://github.com/cloudflare/containers-demos)
