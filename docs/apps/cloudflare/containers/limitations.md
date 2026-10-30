# Cloudflare Containers limitations

Cloudflare Containers is in beta, and the constraints below shape how a workload is built on it.
Cloudflare's [beta info and roadmap](https://developers.cloudflare.com/containers/beta-info/) tracks the planned changes.

## Scaling

| Limitation                | Behavior                  | Workaround                    |
| ------------------------- | ------------------------- | ----------------------------- |
| **No autoscaling**        | Instances managed by hand | `getRandom()` over a pool     |
| **No load balancing**     | Random distribution only  | Custom routing logic          |
| **Manual instance count** | Fixed number of instances | `max_instances` in the config |

A fixed pool routes each request to a random instance:

```typescript
import { getRandom } from "@cloudflare/containers";

const INSTANCE_COUNT = 5;

export default {
  async fetch(request: Request, env: Env) {
    const container = getRandom(env.BACKEND, INSTANCE_COUNT);
    return container.fetch(request);
  },
};
```

The pool size can follow a load metric instead:

```typescript
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

## Resources

| Resource          | Limit                      | Notes                        |
| ----------------- | -------------------------- | ---------------------------- |
| **Instance size** | 4 vCPU, 12 GiB, 20 GB disk | [`standard-4`][types]        |
| **Architecture**  | `linux/amd64` only         | No ARM support               |
| **Max instances** | Account-limited            | Cloudflare raises on request |

A process can watch its own heap and shed caches before it reaches the instance's memory limit:

```javascript
setInterval(() => {
  const used = process.memoryUsage();
  console.log(`Memory: ${Math.round(used.heapUsed / 1024 / 1024)} MB`);
}, 30000);

if (process.memoryUsage().heapUsed > 0.8 * MAX_MEMORY) {
  clearCaches();
}
```

## Storage

| Limitation                | Impact                      | Workaround               |
| ------------------------- | --------------------------- | ------------------------ |
| **Ephemeral disk**        | Data lost on sleep, restart | [DO storage or R2][s]    |
| **No persistent volumes** | No persistent disk mounts   | [R2 FUSE mount][r2]      |
| **DO storage limit**      | 10 GB per Durable Object    | Offload large data to R2 |

## Networking

| Limitation                    | Behavior                    | Workaround               |
| ----------------------------- | --------------------------- | ------------------------ |
| **No direct TCP/UDP**         | Proxied through the Worker  | HTTP or WebSocket        |
| **HTTP-only ingress**         | All traffic via the Worker  | None                     |
| **No container-to-container** | Isolated network namespaces | [Route via a Worker][ir] |

## Operations

| Limitation             | Impact                              | Mitigation           |
| ---------------------- | ----------------------------------- | -------------------- |
| **Log noise**          | Durable Object alarms add log lines | Dashboard filters    |
| **No dashboard links** | Worker-to-container link not shown  | None                 |
| **DO not co-located**  | Latency between DO and container    | None                 |
| **Cold start time**    | 2-3 seconds typical                 | [Smaller images][cs] |

## Fit

Workloads that need production-grade autoscaling, guaranteed SLAs, persistent disk, direct TCP or UDP ingress, or more than 12 GiB of memory do not fit the platform.
It suits development and testing, non-critical production workloads, and projects that tolerate breaking changes.

[cs]: ./cold-starts.md
[ir]: ./internal-routing.md
[r2]: ./r2-mount.md
[s]: ./storage.md
[types]: ./README.md#instance-types
