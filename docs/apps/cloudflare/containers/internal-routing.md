# Cloudflare Containers internal routing

Containers cannot reach each other directly, so a Worker or the Container class carries traffic between ports and services.

## Extra ports

`defaultPort` receives forwarded requests; the class reaches any other port through a TCP socket:

```typescript
export class MyContainer extends Container {
  defaultPort = 8080; // HTTP API

  async getMetrics() {
    // Metrics server on a second port
    const metricsPort = await this.ctx.container.getTcpPort(9090);
  }
}
```

## Container to container

A Worker routes by path to separate container bindings and can chain them, passing one service's output to the next:

```typescript
export default {
  async fetch(request: Request, env: Env) {
    const url = new URL(request.url);

    if (url.pathname.startsWith("/service-a")) {
      return getContainer(env.SERVICE_A, "main").fetch(request);
    }

    if (url.pathname.startsWith("/service-b")) {
      return getContainer(env.SERVICE_B, "main").fetch(request);
    }

    // Orchestrate between services
    if (url.pathname === "/orchestrate") {
      const containerA = getContainer(env.SERVICE_A, "main");
      const resultA = await containerA.fetch(new Request("http://a/data"));
      const dataA = await resultA.json();

      const containerB = getContainer(env.SERVICE_B, "main");
      return containerB.fetch(
        new Request("http://b/process", {
          method: "POST",
          body: JSON.stringify(dataA),
        }),
      );
    }
  },
};
```

Each service is its own Container class with its own binding and migration in [`wrangler.jsonc`](./configuration.md#wrangler-configuration).
