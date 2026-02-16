# Cloudflare Containers Storage & Networking

## Storage Options

### Overview

| Storage Type           | Persistence | Capacity       | Use Case            |
| ---------------------- | ----------- | -------------- | ------------------- |
| Container Disk         | Ephemeral   | 2-20 GB        | Temp files, cache   |
| Durable Object Storage | Persistent  | Up to 10 GB    | App state, metadata |
| R2 (FUSE Mount)        | Persistent  | Unlimited      | Files, large data   |
| Workers KV             | Persistent  | Per-key limits | Config, sessions    |

## Container Disk (Ephemeral)

### Characteristics

- **Ephemeral**: Cleared on every restart/sleep
- **Size**: Determined by instance type (2-20 GB)
- **Performance**: Fast, local SSD-like
- **Access**: Standard filesystem operations

### Disk Size by Instance Type

| Instance Type | Disk Space |
| ------------- | ---------- |
| `lite`        | 2 GB       |
| `basic`       | 4 GB       |
| `standard-1`  | 8 GB       |
| `standard-2`  | 12 GB      |
| `standard-3`  | 16 GB      |
| `standard-4`  | 20 GB      |

### Use Cases

```bash
# Good uses for ephemeral disk
/tmp/                  # Temporary files
/var/cache/            # Runtime caches
/app/uploads/temp/     # Processing uploads before moving to R2

# Bad uses (data will be lost)
/data/database.sqlite  # Database files
/app/user_uploads/     # Permanent user files
/var/log/persistent/   # Logs you need to keep
```

## Durable Object Storage

Since Container extends DurableObject, you have full access to persistent storage.

### SQLite Storage (Recommended)

```typescript
export class MyContainer extends Container {
  // Initialize tables
  async initStorage() {
    await this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        data TEXT,
        created_at INTEGER
      )
    `);
  }

  // Store data
  async saveSession(id: string, userId: string, data: object) {
    await this.ctx.storage.sql.exec(
      `INSERT OR REPLACE INTO sessions (id, user_id, data, created_at)
       VALUES (?, ?, ?, ?)`,
      id,
      userId,
      JSON.stringify(data),
      Date.now(),
    );
  }

  // Retrieve data
  async getSession(id: string) {
    const result = await this.ctx.storage.sql.exec(
      `SELECT * FROM sessions WHERE id = ?`,
      id,
    );
    return result.rows[0];
  }
}
```

### Key-Value Storage

```typescript
export class MyContainer extends Container {
  // Simple key-value operations
  async saveConfig(config: object) {
    await this.ctx.storage.put("config", config);
  }

  async getConfig() {
    return await this.ctx.storage.get("config");
  }

  // Multiple keys
  async saveMultiple(data: Map<string, any>) {
    await this.ctx.storage.put(Object.fromEntries(data));
  }

  async getMultiple(keys: string[]) {
    return await this.ctx.storage.get(keys);
  }

  // Delete
  async clearSession(id: string) {
    await this.ctx.storage.delete(`session:${id}`);
  }
}
```

### Storage Limits

| Metric         | Limit                        |
| -------------- | ---------------------------- |
| Storage per DO | Up to 10 GB (SQLite backend) |
| Key size       | 2 KB max                     |
| Value size     | 128 KB max (KV API)          |

## R2 FUSE Mount

Mount R2 buckets as filesystems for persistent file storage.

### Setup

#### 1. Dockerfile Configuration

```dockerfile
FROM alpine:3.20

# Install FUSE and dependencies
RUN apk add --no-cache \
    ca-certificates fuse curl bash

# Install tigrisfs (R2-compatible FUSE adapter)
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then ARCH="amd64"; fi && \
    VERSION=$(curl -s https://api.github.com/repos/tigrisdata/tigrisfs/releases/latest | grep tag_name | cut -d'"' -f4) && \
    curl -L "https://github.com/tigrisdata/tigrisfs/releases/download/${VERSION}/tigrisfs_Linux_${ARCH}.tar.gz" | tar xz -C /usr/local/bin

# Startup script
RUN echo '#!/bin/bash\n\
mkdir -p /mnt/r2\n\
R2_ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"\n\
tigrisfs --endpoint "${R2_ENDPOINT}" -f "${R2_BUCKET_NAME}" /mnt/r2 &\n\
sleep 3\n\
exec "$@"' > /startup.sh && chmod +x /startup.sh

EXPOSE 8080
ENTRYPOINT ["/startup.sh"]
CMD ["node", "server.js"]
```

#### 2. Container Class Configuration

```typescript
export class MyContainer extends Container {
  defaultPort = 8080;
  sleepAfter = "10m";

  envVars = {
    AWS_ACCESS_KEY_ID: this.env.R2_ACCESS_KEY,
    AWS_SECRET_ACCESS_KEY: this.env.R2_SECRET_KEY,
    R2_BUCKET_NAME: this.env.R2_BUCKET,
    R2_ACCOUNT_ID: this.env.CF_ACCOUNT_ID,
  };
}
```

#### 3. Wrangler Configuration

```jsonc
{
  "vars": {
    "R2_BUCKET": "my-bucket",
    "CF_ACCOUNT_ID": "your-account-id",
  },
  // R2_ACCESS_KEY and R2_SECRET_KEY should be secrets
}
```

### Creating R2 Credentials

1. Go to [R2 Dashboard](https://dash.cloudflare.com/?to=/:account/r2/overview)
2. Create new R2 API Token
3. Copy Access Key ID → `R2_ACCESS_KEY`
4. Copy Secret Access Key → `R2_SECRET_KEY`

```bash
npx wrangler secret put R2_ACCESS_KEY
npx wrangler secret put R2_SECRET_KEY
```

### Performance Considerations

> **Warning**: Object storage is not a POSIX-compatible filesystem. Do not expect native SSD-like performance.

| Operation           | Performance | Notes                     |
| ------------------- | ----------- | ------------------------- |
| Sequential read     | Good        | Streaming large files     |
| Sequential write    | Good        | Uploading new files       |
| Random read         | Slow        | Many small reads          |
| Random write        | Very slow   | Object storage limitation |
| Metadata operations | Slow        | Listing, stat calls       |

### Appropriate Use Cases

```
✅ Good for:
   • Storing large files (images, videos, documents)
   • Read-heavy workloads
   • Sharing files between container instances
   • Bootstrap data loading

❌ Bad for:
   • Database files (SQLite, etc.)
   • High-frequency small writes
   • Applications requiring POSIX guarantees
   • Latency-sensitive operations
```

### Read-Only Mount

For better performance and safety:

```bash
# In startup script
tigrisfs --endpoint "${R2_ENDPOINT}" -o ro -f "${R2_BUCKET}" /mnt/r2 &
```

## Networking

### Ingress (Incoming Traffic)

#### HTTP Requests

All HTTP traffic must go through a Worker:

```typescript
export default {
  async fetch(request: Request, env: Env) {
    const container = getContainer(env.MY_CONTAINER, "main");
    return container.fetch(request);
  },
};
```

#### WebSocket Connections

WebSockets are supported via Worker upgrade:

```typescript
export default {
  async fetch(request: Request, env: Env) {
    // Check for WebSocket upgrade
    if (request.headers.get("Upgrade") === "websocket") {
      const container = getContainer(env.MY_CONTAINER, "ws-server");
      return container.fetch(request);
    }

    return new Response("Use WebSocket", { status: 400 });
  },
};
```

Container WebSocket server example (Node.js):

```javascript
// server.js in container
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

#### Restrictions

| Traffic Type | Supported | Via                                   |
| ------------ | --------- | ------------------------------------- |
| HTTP         | ✅        | Worker proxy                          |
| HTTPS        | ✅        | Worker proxy (TLS terminated at edge) |
| WebSocket    | ✅        | Worker upgrade                        |
| Direct TCP   | ❌        | Not from end-users                    |
| Direct UDP   | ❌        | Not from end-users                    |
| gRPC         | ✅        | Via HTTP/2 through Worker             |

### Egress (Outgoing Traffic)

Containers have full outbound internet access.

#### HTTP/HTTPS Requests

```javascript
// Inside container
const response = await fetch("https://api.example.com/data");
const data = await response.json();
```

#### TCP Connections

```javascript
// Database connection from container
const { Client } = require("pg");
const client = new Client({
  host: "db.example.com",
  port: 5432,
  user: "user",
  password: process.env.DB_PASSWORD,
});
await client.connect();
```

#### Egress Pricing

- Billed per GB transferred
- Check [pricing documentation](https://developers.cloudflare.com/containers/pricing/) for current rates

### Internal Communication

#### Worker to Container (Multiple Ports)

```typescript
export class MyContainer extends Container {
  defaultPort = 8080; // HTTP API

  async getMetrics() {
    // Access different port for metrics
    const metricsPort = await this.ctx.container.getTcpPort(9090);
    // Use metricsPort for metrics collection
  }
}
```

#### Container to External Services

```typescript
export class MyContainer extends Container {
  envVars = {
    DATABASE_URL: this.env.DATABASE_URL,
    REDIS_URL: this.env.REDIS_URL,
    API_ENDPOINT: "https://api.example.com",
  };
}
```

### DNS Resolution

Containers can resolve public DNS:

```javascript
// Works inside container
const dns = require("dns");
dns.lookup("api.example.com", (err, address) => {
  console.log("Resolved:", address);
});
```

### Network Isolation

Each container runs in isolated network namespace:

- Cannot communicate with other containers directly
- Must go through Worker/DO for container-to-container communication
- Full isolation from other tenants

### Container-to-Container Communication

```typescript
// Worker handling cross-container communication
export default {
  async fetch(request: Request, env: Env) {
    const url = new URL(request.url);

    if (url.pathname.startsWith("/service-a")) {
      const containerA = getContainer(env.SERVICE_A, "main");
      return containerA.fetch(request);
    }

    if (url.pathname.startsWith("/service-b")) {
      const containerB = getContainer(env.SERVICE_B, "main");
      return containerB.fetch(request);
    }

    // Orchestrate between services
    if (url.pathname === "/orchestrate") {
      const containerA = getContainer(env.SERVICE_A, "main");
      const resultA = await containerA.fetch(new Request("http://a/data"));
      const dataA = await resultA.json();

      const containerB = getContainer(env.SERVICE_B, "main");
      const resultB = await containerB.fetch(
        new Request("http://b/process", {
          method: "POST",
          body: JSON.stringify(dataA),
        }),
      );

      return resultB;
    }
  },
};
```

## Best Practices

### Storage

1. **Use appropriate storage for each use case**
   - Ephemeral disk: temp files, caches
   - DO Storage: app state, session data
   - R2: large files, shared data

2. **Don't store critical data on ephemeral disk**

   ```typescript
   // Bad
   fs.writeFileSync("/data/important.json", data);

   // Good
   await this.ctx.storage.put("important", data);
   ```

3. **Initialize DO storage on first run**
   ```typescript
   async onStart() {
     await this.initStorage();
   }
   ```

### Networking

1. **Validate requests in Worker before forwarding**

   ```typescript
   export default {
     async fetch(request: Request, env: Env) {
       // Validate before incurring container cost
       if (!isValidRequest(request)) {
         return new Response("Invalid", { status: 400 });
       }
       return getContainer(env.MY_CONTAINER, "main").fetch(request);
     },
   };
   ```

2. **Handle WebSocket upgrades explicitly**

   ```typescript
   if (request.headers.get("Upgrade") !== "websocket") {
     return new Response("Expected WebSocket", { status: 426 });
   }
   ```

3. **Use connection pooling for database connections**
   ```javascript
   // Inside container
   const pool = new Pool({ max: 10 });
   ```
