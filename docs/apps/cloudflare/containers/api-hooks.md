# Cloudflare Containers API hooks

A Container subclass overrides status hooks to run code on lifecycle events.

| Hook             | Called when                 | Typical work                 |
| ---------------- | --------------------------- | ---------------------------- |
| `onStart()`      | The container starts        | Initialize resources, notify |
| `onStop()`       | The container stops         | Clean up, save state, notify |
| `onError(error)` | The container hits an error | Log, alert, attempt recovery |

An out-of-memory kill also calls `onError` ([out of memory](./lifecycle.md#out-of-memory)).

## Complete example

The class records its start time in Durable Object storage, reports its runtime on stop, and routes each session to its own instance.

```typescript
import { Container, getContainer } from "@cloudflare/containers";

interface Env {
  MY_CONTAINER: DurableObjectNamespace<MyContainer>;
  API_KEY: string;
}

export class MyContainer extends Container<Env> {
  defaultPort = 8080;
  sleepAfter = "10m";

  envVars = {
    API_KEY: this.env.API_KEY,
    NODE_ENV: "production",
  };

  async onStart() {
    console.log("Container starting...");
    await this.ctx.storage.put("startedAt", Date.now());
  }

  async onStop() {
    console.log("Container stopping...");
    const startedAt = await this.ctx.storage.get("startedAt");
    const runtime = Date.now() - (startedAt as number);
    console.log(`Container ran for ${runtime}ms`);
  }

  async onError(error: Error) {
    console.error("Container error:", error.message);
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const sessionId = url.searchParams.get("session") || "default";

    const container = getContainer(env.MY_CONTAINER, sessionId);
    return container.fetch(request);
  },
};
```
