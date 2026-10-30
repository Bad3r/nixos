# Cloudflare Containers networking

All inbound traffic reaches a container through its Worker; outbound traffic goes straight to the internet.

## Ingress

| Traffic type | Supported | Via                            |
| ------------ | --------- | ------------------------------ |
| HTTP         | Yes       | Worker proxy                   |
| HTTPS        | Yes       | Worker proxy, TLS ends at edge |
| WebSocket    | Yes       | Worker upgrade                 |
| gRPC         | Yes       | HTTP/2 through the Worker      |
| Direct TCP   | No        | Not from end users             |
| Direct UDP   | No        | Not from end users             |
| Raw sockets  | No        | Not from end users             |

The Worker validates a request before forwarding it, so an invalid request never incurs container cost:

```typescript
export default {
  async fetch(request: Request, env: Env) {
    if (!isValidRequest(request)) {
      return new Response("Invalid", { status: 400 });
    }
    return getContainer(env.MY_CONTAINER, "main").fetch(request);
  },
};
```

### WebSockets

The Worker checks the upgrade header explicitly and forwards the upgrade to the container:

```typescript
export default {
  async fetch(request: Request, env: Env) {
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("Expected WebSocket", { status: 426 });
    }
    const container = getContainer(env.MY_CONTAINER, "ws-server");
    return container.fetch(request);
  },
};
```

The container runs an ordinary WebSocket server on its default port:

```javascript
// server.js in the container
const WebSocket = require("ws");
const http = require("http");

const server = http.createServer();
const wss = new WebSocket.Server({ server });

wss.on("connection", (ws) => {
  ws.on("message", (message) => {
    ws.send(`Echo: ${message}`);
  });
});

server.listen(8080);
```

## Egress

Containers have full outbound internet access, including HTTP and TCP connections to external services, and outbound access can be restricted through configuration.
Egress is billed per GB transferred ([pricing](https://developers.cloudflare.com/containers/pricing/)).

```javascript
// Database connection from the container
const { Client } = require("pg");
const client = new Client({
  host: "db.example.com",
  port: 5432,
  user: "user",
  password: process.env.DB_PASSWORD,
});
await client.connect();
```

A connection pool keeps database connections bounded:

```javascript
const pool = new Pool({ max: 10 });
```

Service URLs and credentials reach the container through [`envVars`](./deployment.md#passing-values-to-the-container).

### DNS

Containers resolve public DNS names with the runtime's ordinary resolver, such as Node's `dns.lookup`.

## Isolation

Each container runs in an isolated network namespace:

- It cannot reach other containers directly.
- Container-to-container traffic goes through a Worker or Durable Object ([internal routing](./internal-routing.md)).
- It is fully isolated from other tenants.
