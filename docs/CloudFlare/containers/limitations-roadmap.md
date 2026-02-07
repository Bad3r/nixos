# Cloudflare Containers Limitations & Roadmap

> **Status**: Beta
> **Last Updated**: February 2026

## Current Beta Limitations

### Scaling Limitations

| Limitation                | Current Behavior               | Workaround                                      |
| ------------------------- | ------------------------------ | ----------------------------------------------- |
| **No autoscaling**        | Must manually manage instances | Use `getRandom()` helper for multiple instances |
| **No load balancing**     | Random distribution only       | Implement custom routing logic                  |
| **Manual instance count** | Fixed number of instances      | Set `max_instances` in config                   |

#### Manual Scaling Example

```typescript
import { getRandom } from "@cloudflare/containers";

const INSTANCE_COUNT = 5;

export default {
  async fetch(request: Request, env: Env) {
    // Randomly route to one of N instances
    const container = getRandom(env.BACKEND, INSTANCE_COUNT);
    return container.fetch(request);
  },
};
```

### Resource Limitations

| Resource          | Current Limit    | Notes                    |
| ----------------- | ---------------- | ------------------------ |
| **Max vCPU**      | 2 cores          | standard-3 instance      |
| **Max Memory**    | 8 GB             | standard-3 instance      |
| **Max Disk**      | 16 GB            | standard-3 instance      |
| **Architecture**  | linux/amd64 only | No ARM support           |
| **Max instances** | Account-limited  | Contact CF for increases |

### Storage Limitations

| Limitation                | Impact                        | Workaround               |
| ------------------------- | ----------------------------- | ------------------------ |
| **Ephemeral disk**        | Data lost on sleep/restart    | Use DO Storage or R2     |
| **No persistent volumes** | Cannot mount persistent disks | Use R2 FUSE mount        |
| **DO Storage limit**      | 10 GB per Durable Object      | Offload large data to R2 |

### Networking Limitations

| Limitation                    | Current Behavior            | Workaround           |
| ----------------------------- | --------------------------- | -------------------- |
| **No direct TCP/UDP**         | Must proxy through Worker   | Use HTTP/WebSocket   |
| **HTTP-only ingress**         | All traffic via Worker      | N/A                  |
| **No container-to-container** | Isolated network namespaces | Route through Worker |

### Operational Limitations

| Limitation             | Impact                                  | Notes               |
| ---------------------- | --------------------------------------- | ------------------- |
| **Log noise**          | DO alarms create extra logs             | Filter in dashboard |
| **No dashboard links** | Can't see Worker→Container relationship | Coming soon         |
| **DO not co-located**  | Latency between DO and Container        | Planned improvement |
| **Cold start time**    | 2-3 seconds typical                     | Optimize image size |

## Beta Roadmap

### Near-Term (Expected Soon)

#### Autoscaling

```typescript
// Coming soon
class MyBackend extends Container {
  autoscale = true; // Enable automatic scaling
  defaultPort = 8080;
}

export default {
  async fetch(request, env) {
    // Will route to nearest ready instance automatically
    return getContainer(env.MY_BACKEND).fetch(request);
  },
};
```

**Features:**

- Utilization-based scaling (CPU, memory)
- Automatic instance creation/termination
- Configurable min/max instances

#### Latency-Aware Routing

```typescript
// Coming soon
const container = getContainer(env.MY_BACKEND);
// Automatically routes to nearest healthy instance
return container.fetch(request);
```

**Features:**

- Route to nearest instance
- Health-aware routing
- Automatic failover

#### Dashboard Integration

- Worker → Container relationship visibility
- Container instance monitoring
- Resource usage graphs
- Log integration

### Medium-Term (Planned)

#### Durable Object Co-location

**Current**: DO and Container may be in different locations

**Planned**: DO will run on same machine as Container

**Impact**: Lower latency, better performance

#### Higher Limits

| Resource      | Current | Planned        |
| ------------- | ------- | -------------- |
| Max instances | Limited | Higher         |
| Max memory    | 8 GB    | Larger options |
| Max vCPU      | 2       | More cores     |

#### Reduced Log Noise

- Automatic filtering of internal DO alarms
- Cleaner log output
- Better debugging experience

### Long-Term (Future)

#### Persistent Disk

> **Note**: Not slated for near-term, but being explored

**Potential features:**

- Persistent volumes that survive restarts
- Mounted at specified paths
- Backed by durable storage

#### Advanced Placement

**Potential features:**

- Region pinning
- Data residency controls
- Custom placement policies

#### Additional Registries

**Current**: Cloudflare Registry, Amazon ECR

**Potential**: Docker Hub, GCR, Azure CR, private registries

## Comparison with Alternatives

### vs. Traditional Kubernetes

| Aspect         | CF Containers            | Kubernetes                 |
| -------------- | ------------------------ | -------------------------- |
| **Setup**      | Zero infrastructure      | Complex cluster management |
| **Scaling**    | Manual (auto coming)     | Sophisticated autoscaling  |
| **Networking** | Simple (HTTP via Worker) | Full network control       |
| **State**      | Built-in DO storage      | External state management  |
| **Cost model** | Pay for runtime          | Pay for nodes              |
| **Cold start** | 2-3 seconds              | Varies (pod scheduling)    |

### vs. AWS Lambda + Container Images

| Aspect                  | CF Containers   | Lambda Containers         |
| ----------------------- | --------------- | ------------------------- |
| **Max runtime**         | Unlimited       | 15 minutes                |
| **Memory**              | Up to 8 GB      | Up to 10 GB               |
| **State**               | Built-in (DO)   | External (DynamoDB, etc.) |
| **Cold start**          | 2-3 seconds     | Similar or higher         |
| **Networking**          | HTTP via Worker | VPC integration           |
| **Global distribution** | Built-in        | Manual multi-region       |

### vs. Fly.io

| Aspect           | CF Containers         | Fly.io            |
| ---------------- | --------------------- | ----------------- |
| **Architecture** | DO + VM               | Firecracker VMs   |
| **State**        | Integrated DO storage | Volumes, Postgres |
| **Scaling**      | Manual (auto coming)  | Autoscaling       |
| **Networking**   | HTTP only (ingress)   | Full network      |
| **Edge network** | Cloudflare global     | Fly.io regions    |
| **Pricing**      | Per-10ms runtime      | Per-VM time       |

## Working Within Limitations

### Handling No Autoscaling

```typescript
// Strategy 1: Fixed pool with random routing
const POOL_SIZE = 10;
export default {
  async fetch(request, env) {
    return getRandom(env.BACKEND, POOL_SIZE).fetch(request);
  },
};

// Strategy 2: Dynamic scaling based on metrics
export default {
  async fetch(request, env) {
    const metrics = await getMetrics();
    const instanceCount = Math.min(
      Math.ceil(metrics.qps / 100), // 100 QPS per instance
      50, // Max instances
    );
    return getRandom(env.BACKEND, instanceCount).fetch(request);
  },
};
```

### Handling Ephemeral Disk

```typescript
class MyContainer extends Container {
  async onStart() {
    // Load state from DO storage to disk cache
    const state = await this.ctx.storage.get("appState");
    if (state) {
      await this.loadStateToContainer(state);
    }
  }

  async onStop() {
    // Save important state before shutdown
    const state = await this.extractStateFromContainer();
    await this.ctx.storage.put("appState", state);
  }
}
```

### Handling Cold Starts

```typescript
// Strategy 1: Keep-warm with periodic requests
export default {
  async scheduled(event, env, ctx) {
    // Ping container every 5 minutes to keep warm
    const container = getContainer(env.BACKEND, "main");
    await container.fetch(new Request("http://container/health"));
  },

  async fetch(request, env) {
    return getContainer(env.BACKEND, "main").fetch(request);
  },
};

// Strategy 2: Pre-warm pool on deploy
export default {
  async fetch(request, env) {
    // Start multiple instances in parallel
    const warmPromises = [];
    for (let i = 0; i < 5; i++) {
      const c = getContainer(env.BACKEND, `instance-${i}`);
      warmPromises.push(c.startAndWaitForPorts());
    }
    await Promise.all(warmPromises);

    // Route request
    return getRandom(env.BACKEND, 5).fetch(request);
  },
};
```

### Optimizing for Beta Constraints

#### Image Optimization

```dockerfile
# Minimize image size for faster cold starts
FROM alpine:3.20  # 5 MB base

# Install only what you need
RUN apk add --no-cache nodejs npm

# Use multi-stage builds
FROM node:20 AS builder
COPY . .
RUN npm run build

FROM node:20-alpine
COPY --from=builder /app/dist ./dist
```

#### Memory Management

```javascript
// Monitor memory usage
setInterval(() => {
  const used = process.memoryUsage();
  console.log(`Memory: ${Math.round(used.heapUsed / 1024 / 1024)} MB`);
}, 30000);

// Graceful degradation
if (process.memoryUsage().heapUsed > 0.8 * MAX_MEMORY) {
  clearCaches();
}
```

## Feedback & Feature Requests

### Providing Feedback

- [Cloudflare Community Forums](https://community.cloudflare.com/)
- [GitHub Issues](https://github.com/cloudflare/cloudflare-docs/issues)
- [Containers Feedback Form](https://forms.gle/AGSq54VvUje6kmKu8)

### Commonly Requested Features

Based on community feedback:

1. **Autoscaling** - Most requested, in development
2. **Persistent disk** - Needed for databases, caches
3. **ARM support** - For cost efficiency
4. **Direct TCP/UDP** - For game servers, custom protocols
5. **Larger instances** - For ML, video processing
6. **Multi-region pinning** - For data residency

## Migration Considerations

### When to Wait for GA

Consider waiting if you need:

- Production-grade autoscaling
- Guaranteed SLAs
- Persistent disk
- Direct TCP/UDP ingress
- Very large instances (>8GB RAM)

### Safe for Beta Use

The beta is suitable for:

- Development and testing
- Non-critical production workloads
- Use cases that work within current limits
- Projects that can handle occasional breaking changes

### Preparing for GA

```typescript
// Write code that will work with future autoscaling
class MyContainer extends Container {
  defaultPort = 8080;
  sleepAfter = "10m";
  // Ready for: autoscale = true;
}

// Use getContainer pattern (future-proof)
export default {
  async fetch(request, env) {
    const container = getContainer(env.BACKEND, "main");
    // When autoscaling arrives, this will work automatically
    return container.fetch(request);
  },
};
```
