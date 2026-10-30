# Cloudflare Containers lifecycle

A container moves between four states; a request or `start()` brings it up, and inactivity, `stop()`, or an error takes it down.

```text
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
│                    RUNNING                      │       │
│  ┌─────────────────────────────────────────┐    │       │
│  │ Processing requests                     │    │       │
│  │ Executing background tasks              │    │       │
│  └─────────────────────────────────────────┘    │       │
└─────────────────────────┬───────────────────────┘       │
                          │                               │
          ┌───────────────┼───────────────┐               │
          │               │               │               │
          ▼               ▼               ▼               │
   sleepAfter        stop()          OOM/Error            │
   elapsed           called          occurred             │
          │               │               │               │
          └───────────────┼───────────────┘               │
                          │                               │
                          ▼                               │
                ┌──────────────┐                          │
                │   STOPPING   │──────────────────────────┘
                │  (SIGTERM)   │
                └──────────────┘
```

| State        | Description                     |
| ------------ | ------------------------------- |
| **STOPPED**  | Not running; disk is cleared    |
| **STARTING** | Image loading, process starting |
| **RUNNING**  | Active and processing requests  |
| **STOPPING** | Graceful shutdown, SIGTERM sent |

Starting from STOPPED is a [cold start](./cold-starts.md); STOPPING follows the [shutdown sequence](./shutdown.md).
The disk is ephemeral, so state that must survive a stop goes to [Durable Object storage or R2](./storage.md).

## Sleep

`sleepAfter` sets how long a container stays up after its last request:

```typescript
export class MyContainer extends Container {
  sleepAfter = "10m"; // Sleep after 10 minutes of inactivity
}
```

```text
Last Request Completes
         │
         ▼
┌─────────────────────────────────────┐
│        Inactivity Period            │
│   (sleepAfter countdown running)    │
├─────────────────────────────────────┤
│   New request? ─────► Reset timer   │
│                       Stay running  │
│                                     │
│   No request for sleepAfter?        │
│         │                           │
│         ▼                           │
│   Begin shutdown                    │
└─────────────────────────────────────┘
```

| Use case           | Value               | Reason                      |
| ------------------ | ------------------- | --------------------------- |
| Interactive apps   | `"5m"` to `"15m"`   | Responsiveness against cost |
| Batch jobs         | `"1m"` or less      | Short-lived, cost-sensitive |
| Dev environments   | `"30m"` to `"2h"`   | Infrequent access, UX first |
| Always-on services | Not set / very long | Avoids cold starts entirely |

A long-running container sets a very long timeout such as `"24h"`; the behavior with `sleepAfter` unset varies.

## Out of memory

When a container exceeds its instance type's memory:

1. The container process is killed immediately.
2. The `onError` hook runs, if defined.
3. The container enters STOPPED.
4. The next request triggers a cold start.

```typescript
export class MyContainer extends Container {
  async onError(error: Error) {
    if (error.message.includes("OOM")) {
      console.error("Container ran out of memory");
    }
  }
}
```

The fix is a larger `instance_type` in `wrangler.jsonc` ([instance types](./README.md#instance-types)).

## Instance lifetime

A container has no hard runtime limit and runs indefinitely while it receives requests.
Host server maintenance restarts it:

1. SIGTERM goes to the container.
2. The 15-minute grace period runs.
3. The container moves to a new host.
4. The new instance starts with a cold start.
