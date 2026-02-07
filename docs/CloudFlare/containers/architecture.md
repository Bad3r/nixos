# Cloudflare Containers Architecture

## System Overview

Cloudflare Containers combines three core Cloudflare technologies:

1. **Workers** - Edge compute for request routing and authentication
2. **Durable Objects** - Stateful coordination and container lifecycle management
3. **Container VMs** - Isolated execution environments

```
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

## Component Responsibilities

### Worker Layer

| Responsibility    | Description                                            |
| ----------------- | ------------------------------------------------------ |
| Request Routing   | Direct requests to appropriate container instances     |
| Authentication    | Validate requests before container invocation          |
| Load Distribution | Route to specific instances via ID or random selection |
| Protocol Handling | Handle HTTP, WebSocket upgrades                        |

### Durable Object Layer

| Responsibility          | Description                                 |
| ----------------------- | ------------------------------------------- |
| Container Orchestration | Start, stop, signal containers              |
| State Storage           | SQLite-backed persistent state (up to 10GB) |
| Lifecycle Hooks         | Execute code on start/stop/error events     |
| Global Addressing       | Route to containers regardless of location  |
| Alarms                  | Schedule recurring checks and maintenance   |

### Container VM Layer

| Responsibility     | Description                             |
| ------------------ | --------------------------------------- |
| Isolated Execution | Full VM isolation (not just namespaces) |
| Any Runtime        | Run any linux/amd64 Docker image        |
| Network Access     | Outbound internet, internal ports       |
| Filesystem         | Ephemeral disk per instance type        |

## Request Flow

### 1. Client to Worker

```
Client Request
     │
     ▼
┌─────────────────────────────────────────┐
│              Cloudflare Edge            │
│  ┌─────────────────────────────────┐    │
│  │  Nearest datacenter (or Smart   │    │
│  │  Placement optimized location)  │    │
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
```

- Request hits nearest edge location
- Smart Placement may select different location for optimization
- Heavy load may redirect to alternative location

### 2. Worker to Durable Object

```typescript
// Worker code
const container = getContainer(env.MY_CONTAINER, "user-123");
return container.fetch(request);
```

- Worker invokes Durable Object by ID
- Durable Object is globally routable
- Same ID always routes to same DO instance

### 3. Durable Object to Container

```
Durable Object
     │
     ▼ Selects nearest location with pre-fetched image
     │
┌─────────────────────────────────────────┐
│          Container Location             │
│  ┌─────────────────────────────────┐    │
│  │     VM with Container Image     │    │
│  │     ┌─────────────────────┐     │    │
│  │     │   Your Application  │     │    │
│  │     └─────────────────────┘     │    │
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
```

## Image Distribution

### Deployment Process

1. **Build**: Wrangler builds image locally via Docker
2. **Push**: Image pushed to Cloudflare Registry (backed by R2)
3. **Distribute**: Image pre-fetched to global locations
4. **Pre-warm**: Instances pre-scheduled for quick starts

```
┌──────────┐    ┌─────────────┐    ┌──────────────────┐
│  Docker  │───▶│  Cloudflare │───▶│  Global Edge     │
│  Build   │    │  Registry   │    │  Pre-fetch       │
└──────────┘    │  (R2-backed)│    │  Locations       │
                └─────────────┘    └──────────────────┘
```

### Registry Sources

| Source                          | Description                                |
| ------------------------------- | ------------------------------------------ |
| `./Dockerfile`                  | Build locally, push to Cloudflare Registry |
| `registry.cloudflare.com/...`   | Pre-built image in Cloudflare Registry     |
| `*.dkr.ecr.*.amazonaws.com/...` | Amazon ECR (requires credential setup)     |

## Container Runtime

### Isolation Model

Each container runs in its own **VM** (not just container namespaces):

- Strong isolation from other workloads
- Dedicated kernel per container
- No shared resources with other tenants

### Architecture Requirements

- **Platform**: `linux/amd64` only
- **No ARM support** currently

### Resource Allocation

Resources are fixed per instance type:

```
┌─────────────────────────────────────┐
│         Container VM                │
│  ┌─────────────────────────────┐    │
│  │  vCPU: 1/16 to 2 cores     │    │
│  │  Memory: 256MB to 8GB      │    │
│  │  Disk: 2GB to 16GB         │    │
│  └─────────────────────────────┘    │
└─────────────────────────────────────┘
```

## Location Selection

### Initial Request (Cold Start)

When starting a new container:

1. Find nearest location with pre-fetched image
2. Start container VM at that location
3. Route request to new container

### Subsequent Requests (Warm)

While container is running:

1. All requests route to existing container location
2. Location may be distant from user
3. Container stays at same location until sleep

### After Sleep

When container restarts:

1. New location may be selected
2. Based on requesting user's location
3. Different from previous location possible

## Network Architecture

### Ingress Restrictions

```
┌──────────────────────────────────────────────┐
│                 ALLOWED                       │
│  ┌────────────────────────────────────────┐  │
│  │  HTTP Requests (via Worker)            │  │
│  │  WebSocket Connections (via Worker)    │  │
│  └────────────────────────────────────────┘  │
├──────────────────────────────────────────────┤
│                 NOT ALLOWED                   │
│  ┌────────────────────────────────────────┐  │
│  │  Direct TCP from end-users             │  │
│  │  Direct UDP from end-users             │  │
│  │  Raw socket connections                │  │
│  └────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
```

### Egress Capabilities

- Full outbound internet access
- TCP connections to external services
- Can be restricted via configuration

## Rollout Strategy

### Default Behavior

1. **Step 1**: Update 10% of instances
2. **Step 2**: Update remaining 90%

### Configurable Parameters

| Parameter                     | Description                                         |
| ----------------------------- | --------------------------------------------------- |
| `rollout_step_percentage`     | Percentage for first rollout step                   |
| `rollout_active_grace_period` | Seconds before active container eligible for update |

### Graceful Shutdown

```
New Deploy
    │
    ▼
┌─────────────────┐
│ SIGTERM sent    │
│ to container    │
└────────┬────────┘
         │
         ▼ (up to 15 minutes for cleanup)
         │
┌────────▼────────┐
│ SIGKILL if      │
│ still running   │
└─────────────────┘
```
