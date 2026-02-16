# Cloudflare Containers Lifecycle Management

## Container States

```
                    ┌──────────────┐
                    │   STOPPED    │◄─────────────────────────┐
                    └──────┬───────┘                          │
                           │                                  │
                           │ start() / first request          │
                           ▼                                  │
                    ┌──────────────┐                          │
                    │   STARTING   │                          │
                    └──────┬───────┘                          │
                           │                                  │
                           │ ports ready                      │
                           ▼                                  │
    ┌─────────────────────────────────────────────────┐       │
    │                    RUNNING                       │       │
    │  ┌─────────────────────────────────────────┐    │       │
    │  │ Processing requests                      │    │       │
    │  │ Executing background tasks               │    │       │
    │  └─────────────────────────────────────────┘    │       │
    └─────────────────────────┬───────────────────────┘       │
                              │                               │
              ┌───────────────┼───────────────┐               │
              │               │               │               │
              ▼               ▼               ▼               │
       sleepAfter        stop()          OOM/Error           │
       elapsed           called          occurred            │
              │               │               │               │
              └───────────────┼───────────────┘               │
                              │                               │
                              ▼                               │
                    ┌──────────────┐                          │
                    │   STOPPING   │──────────────────────────┘
                    │  (SIGTERM)   │
                    └──────────────┘
```

## State Descriptions

| State        | Description                                  |
| ------------ | -------------------------------------------- |
| **STOPPED**  | Container is not running; disk is cleared    |
| **STARTING** | Container image loading, process starting    |
| **RUNNING**  | Container is active and processing requests  |
| **STOPPING** | Graceful shutdown in progress (SIGTERM sent) |

## Cold Starts

### What is a Cold Start?

A cold start occurs when a container must be started from a completely stopped state:

- First request to a new container ID
- Request after container has slept
- Request after OOM or error termination

### Cold Start Timeline

```
Request Arrives
      │
      ▼
┌─────────────────┐
│ Select location │  ~50-100ms
│ with image      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Start VM        │  ~500ms-1s
│                 │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Load container  │  ~500ms-2s
│ image           │  (depends on size)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Run entrypoint  │  Variable
│ & dependencies  │  (app-specific)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Ready to serve  │
│ requests        │
└─────────────────┘

Total: Typically 2-3 seconds
```

### Factors Affecting Cold Start Time

| Factor                | Impact               | Optimization                          |
| --------------------- | -------------------- | ------------------------------------- |
| Image size            | Larger = slower      | Use multi-stage builds, alpine base   |
| Dependencies          | More = slower        | Lazy load, minimize imports           |
| Entrypoint complexity | More work = slower   | Defer non-critical initialization     |
| Runtime               | Interpreted = slower | Use compiled languages for fast start |

### Optimizing Cold Starts

```dockerfile
# Bad: Large image, many dependencies
FROM node:20
COPY . .
RUN npm install
CMD ["node", "server.js"]

# Good: Small image, production deps only
FROM node:20-alpine AS builder
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-alpine
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
CMD ["node", "dist/server.js"]
```

## Warm Requests

### What is a Warm Request?

A warm request occurs when the container is already running:

- `sleepAfter` timeout has not elapsed
- Container is actively processing requests
- No errors or OOM conditions

### Warm Request Performance

```
Request Arrives
      │
      ▼
┌─────────────────┐
│ Route to        │  ~1-10ms
│ running         │  (network latency)
│ container       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Process         │  App-specific
│ request         │
└─────────────────┘

Total: Milliseconds (dominated by app processing time)
```

## Sleep Behavior

### sleepAfter Property

```typescript
export class MyContainer extends Container {
  sleepAfter = "10m"; // Sleep after 10 minutes of inactivity
}
```

### Sleep Timeline

```
Last Request Completes
         │
         ▼
┌─────────────────────────────────────┐
│        Inactivity Period            │
│   (sleepAfter countdown running)    │
├─────────────────────────────────────┤
│                                     │
│   New request? ─────► Reset timer   │
│                       Stay running  │
│                                     │
│   No request for sleepAfter?        │
│         │                           │
│         ▼                           │
│   Begin shutdown                    │
│                                     │
└─────────────────────────────────────┘
```

### Recommended sleepAfter Values

| Use Case           | Recommended Value   | Reason                            |
| ------------------ | ------------------- | --------------------------------- |
| Interactive apps   | `"5m"` to `"15m"`   | Balance responsiveness and cost   |
| Batch jobs         | `"1m"` or less      | Short-lived, cost-sensitive       |
| Dev environments   | `"30m"` to `"2h"`   | Less frequent access, UX priority |
| Always-on services | Not set / very long | Avoid cold starts entirely        |

## Shutdown Process

### Graceful Shutdown

```
Shutdown Triggered
(sleepAfter / stop() / deploy)
         │
         ▼
┌─────────────────┐
│  SIGTERM sent   │
│  to container   │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────┐
│     15-Minute Grace Period          │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ Application should:          │    │
│  │ • Finish active requests     │    │
│  │ • Close DB connections       │    │
│  │ • Flush logs/metrics         │    │
│  │ • Save state if needed       │    │
│  │ • Exit cleanly               │    │
│  └─────────────────────────────┘    │
│                                     │
└─────────────────────────────────────┘
         │
         ▼
┌─────────────────┐
│ Process exited? │
│                 │
├────Yes──────────┼────No─────────────┐
│                 │                   │
▼                 │                   ▼
Container         │           ┌───────────────┐
stopped           │           │ SIGKILL sent  │
cleanly           │           │ (forced kill) │
                  │           └───────────────┘
```

### Handling SIGTERM

```javascript
// Node.js example
process.on("SIGTERM", async () => {
  console.log("SIGTERM received, shutting down gracefully");

  // Stop accepting new requests
  server.close();

  // Wait for active requests to complete
  await Promise.all(activeRequests);

  // Close database connections
  await db.close();

  // Flush logs
  await logger.flush();

  console.log("Shutdown complete");
  process.exit(0);
});
```

```python
# Python example
import signal
import sys

def handle_sigterm(signum, frame):
    print("SIGTERM received, shutting down gracefully")
    # Cleanup code here
    sys.exit(0)

signal.signal(signal.SIGTERM, handle_sigterm)
```

```go
// Go example
sigChan := make(chan os.Signal, 1)
signal.Notify(sigChan, syscall.SIGTERM)

go func() {
    <-sigChan
    log.Println("SIGTERM received, shutting down")

    // Cleanup
    server.Shutdown(context.Background())
    db.Close()

    os.Exit(0)
}()
```

## Out of Memory (OOM)

### OOM Behavior

When a container exceeds its memory limit:

1. Container process is killed immediately
2. `onError` hook is triggered (if defined)
3. Container enters STOPPED state
4. Next request triggers cold start

### Preventing OOM

```typescript
export class MyContainer extends Container {
  // Use appropriate instance type for workload
  // Configure in wrangler.jsonc: "instance_type": "standard-2"

  async onError(error: Error) {
    if (error.message.includes("OOM")) {
      console.error("Container ran out of memory");
      // Alert, log metrics, consider larger instance type
    }
  }
}
```

### Memory Limits by Instance Type

| Instance     | Memory  | Recommendation                   |
| ------------ | ------- | -------------------------------- |
| `lite`       | 256 MiB | Simple scripts, lightweight apps |
| `basic`      | 1 GiB   | Typical web services             |
| `standard-1` | 4 GiB   | Memory-intensive apps            |
| `standard-2` | 6 GiB   | Large data processing            |
| `standard-3` | 8 GiB   | Heavy workloads                  |
| `standard-4` | 12 GiB  | Maximum workloads                |

## Disk Behavior

### Ephemeral Disk

**Important**: Container disk is ephemeral and cleared on every restart.

```
Container Running
      │
      ▼
┌─────────────────┐
│  /tmp/data.json │  ← File exists
│  /var/log/app   │  ← Logs exist
└─────────────────┘
      │
      │ Container sleeps/stops
      ▼
┌─────────────────┐
│     (empty)     │  ← All data gone
└─────────────────┘
      │
      │ Container restarts
      ▼
┌─────────────────┐
│  Fresh disk     │  ← From image only
│  from image     │
└─────────────────┘
```

### Persisting Data

Use external storage for persistent data:

```typescript
export class MyContainer extends Container {
  // Use Durable Object storage
  async saveState(data: any) {
    await this.ctx.storage.put("appState", data);
  }

  async loadState() {
    return await this.ctx.storage.get("appState");
  }
}
```

Or use R2 FUSE mount:

```dockerfile
# Mount R2 bucket for persistent storage
RUN apk add fuse
# Configure tigrisfs or s3fs for R2
```

## Rollout Behavior

### During Deployment

```
wrangler deploy
      │
      ▼
┌─────────────────────────────────────┐
│         Rollout Step 1              │
│   Update 10% of instances           │
│                                     │
│   ┌─────────────────────────────┐   │
│   │ Running containers receive  │   │
│   │ SIGTERM after grace period  │   │
│   └─────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────┐
│         Rollout Step 2              │
│   Update remaining 90%              │
│                                     │
└─────────────────────────────────────┘
```

### Rollout Configuration

```jsonc
{
  "containers": [
    {
      "rollout_step_percentage": 10, // First step: 10%
      "rollout_active_grace_period": 300, // Wait 5 min before updating active
    },
  ],
}
```

## Instance Lifetime

### Maximum Runtime

- No hard limit on container runtime
- Containers can run indefinitely if receiving requests
- Host server maintenance may trigger restart

### Host Maintenance

When Cloudflare performs host maintenance:

1. SIGTERM sent to container
2. 15-minute grace period
3. Container migrated to new host
4. New instance starts (cold start)

### Keeping Containers Alive

```typescript
// For long-running containers, use keepAlive pattern
export class MyContainer extends Container {
  sleepAfter = "24h"; // Very long timeout

  // Or don't set sleepAfter at all (default behavior varies)
}
```
