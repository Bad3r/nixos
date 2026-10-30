# Cloudflare Containers shutdown

A container shuts down when `sleepAfter` elapses, when `stop()` is called, on a deploy, and on host maintenance.
Each case sends SIGTERM, allows up to 15 minutes for cleanup, then sends SIGKILL if the process is still running.

```text
Shutdown Triggered
(sleepAfter / stop() / deploy)
         │
         ▼
┌─────────────────┐
│  SIGTERM sent   │
└────────┬────────┘
         │  up to 15 minutes: finish active requests,
         │  close connections, flush logs, save state, exit
         ▼
┌─────────────────┐   yes   ┌──────────────────┐
│ Process exited? │────────▶│ Stopped cleanly  │
└────────┬────────┘         └──────────────────┘
         │ no
         ▼
┌─────────────────┐
│  SIGKILL sent   │
└─────────────────┘
```

## Handling SIGTERM

The application finishes active requests, closes database connections, flushes logs and metrics, saves state it needs, and exits.

```javascript
// Node.js
process.on("SIGTERM", async () => {
  console.log("SIGTERM received, shutting down gracefully");
  server.close(); // stop accepting new requests
  await Promise.all(activeRequests);
  await db.close();
  await logger.flush();
  process.exit(0);
});
```

```python
# Python
import signal
import sys


def handle_sigterm(signum, frame):
    print("SIGTERM received, shutting down gracefully")
    # Cleanup code here
    sys.exit(0)


signal.signal(signal.SIGTERM, handle_sigterm)
```

```go
// Go
sigChan := make(chan os.Signal, 1)
signal.Notify(sigChan, syscall.SIGTERM)

go func() {
    <-sigChan
    log.Println("SIGTERM received, shutting down")
    server.Shutdown(context.Background())
    db.Close()
    os.Exit(0)
}()
```

State that must outlive the container goes to [Durable Object storage](./storage.md#durable-object-storage) before exit, since the disk is cleared.

## Rollouts

`wrangler deploy` replaces running containers in two steps:

1. The first step updates 10% of instances.
2. The second step updates the remaining 90%.

Running containers in each step receive SIGTERM and follow the shutdown sequence above.

| Parameter                     | Description                          |
| ----------------------------- | ------------------------------------ |
| `rollout_step_percentage`     | Percentage for the first step        |
| `rollout_active_grace_period` | Seconds before an active one updates |

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
