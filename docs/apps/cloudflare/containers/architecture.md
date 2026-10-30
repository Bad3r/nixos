# Cloudflare Containers architecture

Cloudflare Containers combines three Cloudflare technologies:

1. **Workers**: edge compute for request routing and authentication.
2. **Durable Objects**: stateful coordination and container lifecycle management.
3. **Container VMs**: isolated execution environments.

```text
┌─────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Client    │────▶│     Worker      │────▶│ Durable Object  │
│             │     │  (routing/auth) │     │ (Container ctrl)│
└─────────────┘     └─────────────────┘     └────────┬────────┘
                                                     │
                                            ┌────────▼────────┐
                                            │   Container VM  │
                                            │  (linux/amd64)  │
                                            └─────────────────┘
```

## Component responsibilities

### Worker layer

| Responsibility    | Description                          |
| ----------------- | ------------------------------------ |
| Request routing   | Directs requests to instances        |
| Authentication    | Validates requests before invocation |
| Load distribution | Picks an instance by ID or at random |
| Protocol handling | HTTP and WebSocket upgrades          |

### Durable Object layer

| Responsibility          | Description                         |
| ----------------------- | ----------------------------------- |
| Container orchestration | Start, stop, and signal containers  |
| State storage           | SQLite-backed state, up to 10 GB    |
| Lifecycle hooks         | Code on start, stop, and error      |
| Global addressing       | Routes to a container from anywhere |
| Alarms                  | Recurring checks and maintenance    |

### Container VM layer

| Responsibility     | Description                       |
| ------------------ | --------------------------------- |
| Isolated execution | Full VM isolation                 |
| Any runtime        | Any linux/amd64 Docker image      |
| Network access     | Outbound internet, internal ports |
| Filesystem         | Ephemeral disk per instance type  |

## Request flow

### Client to Worker

The request reaches the nearest edge location.
Smart Placement may pick a different location for optimization, and heavy load may redirect the request to an alternative location.

### Worker to Durable Object

```typescript
// Worker code
const container = getContainer(env.MY_CONTAINER, "user-123");
return container.fetch(request);
```

The Worker invokes the Durable Object by ID.
A Durable Object is globally routable, and the same ID always routes to the same instance.

### Durable Object to container

The Durable Object starts the container VM at the nearest location holding a [pre-fetched copy of the image](./images.md#distribution), then forwards the request to the application inside it.

## Runtime

### Isolation model

Each container runs in its own VM rather than in shared container namespaces:

- Strong isolation from other workloads.
- A dedicated kernel per container.
- No resources shared with other tenants.

### Platform

Images must target `linux/amd64`; ARM is not supported.
CPU, memory, and disk are fixed per instance type ([instance types](./README.md#instance-types)).

## Location selection

### Cold start

When a new container starts:

1. The Durable Object finds the nearest location with the pre-fetched image.
2. The container VM starts at that location.
3. The request routes to the new container.

### Warm requests

While a container runs, every request routes to its existing location, which may be distant from the user.
The container stays at that location until it sleeps.

### After sleep

When the container [restarts](./lifecycle.md), a new location may be selected based on the requesting user's location.
