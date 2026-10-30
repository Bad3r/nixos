# Cloudflare Containers cold starts

A cold start boots a container from STOPPED; it happens on the first request to a new container ID, after the container has slept, and after an OOM or error termination.
A cold start typically takes 2 to 3 seconds.

## Timeline

```text
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
```

## Factors

| Factor                | Impact               | Optimization                    |
| --------------------- | -------------------- | ------------------------------- |
| Image size            | Larger = slower      | Multi-stage builds, alpine base |
| Dependencies          | More = slower        | Lazy loading, fewer imports     |
| Entrypoint complexity | More work = slower   | Defer non-critical setup        |
| Runtime               | Interpreted = slower | Compiled languages start faster |

The [multi-stage build](./images.md#multi-stage-build) keeps only production dependencies in the final image.

## Warm requests

A request is warm when the container is running: `sleepAfter` has not elapsed and no error or OOM has stopped it.
Routing to a running container adds roughly 1 to 10 ms of network latency, so application processing time dominates a warm request.

## Keeping containers warm

A cron trigger can ping the container so it never reaches `sleepAfter`:

```typescript
export default {
  async scheduled(event, env, ctx) {
    // Runs every 5 minutes from the Worker's cron trigger
    const container = getContainer(env.BACKEND, "main");
    await container.fetch(new Request("http://container/health"));
  },

  async fetch(request, env) {
    return getContainer(env.BACKEND, "main").fetch(request);
  },
};
```

A pool can be started in parallel before routing to it:

```typescript
export default {
  async fetch(request, env) {
    const warmPromises = [];
    for (let i = 0; i < 5; i++) {
      const c = getContainer(env.BACKEND, `instance-${i}`);
      warmPromises.push(c.startAndWaitForPorts());
    }
    await Promise.all(warmPromises);

    return getRandom(env.BACKEND, 5).fetch(request);
  },
};
```
