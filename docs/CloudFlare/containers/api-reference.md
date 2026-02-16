# Cloudflare Containers API Reference

## Installation

```bash
npm install @cloudflare/containers
```

## Container Class

The `Container` class extends `DurableObject` and provides container-specific functionality.

### Basic Definition

```typescript
import { Container } from "@cloudflare/containers";

export class MyContainer extends Container {
  defaultPort = 8080;
  sleepAfter = "10m";
}
```

### Properties

| Property      | Type    | Required | Description                                 |
| ------------- | ------- | -------- | ------------------------------------------- |
| `defaultPort` | number  | Yes      | Port the container listens on               |
| `sleepAfter`  | string  | No       | Inactivity timeout (e.g., "5m", "2h", "1d") |
| `envVars`     | object  | No       | Environment variables for container         |
| `autoscale`   | boolean | No       | Enable autoscaling (unreleased)             |

### Property Examples

```typescript
export class MyContainer extends Container {
  // Required: Port your container listens on
  defaultPort = 8080;

  // Optional: Sleep after 10 minutes of inactivity
  sleepAfter = "10m";

  // Optional: Environment variables
  envVars = {
    NODE_ENV: "production",
    API_KEY: this.env.API_KEY,
    LOG_LEVEL: "info",
  };

  // Future: Autoscaling (not yet released)
  // autoscale = true;
}
```

### Time Duration Format

For `sleepAfter` and similar properties:

| Format  | Example | Duration   |
| ------- | ------- | ---------- |
| Seconds | `"30s"` | 30 seconds |
| Minutes | `"10m"` | 10 minutes |
| Hours   | `"2h"`  | 2 hours    |
| Days    | `"1d"`  | 1 day      |

## Container Methods

### fetch(request)

Forward an HTTP request to the container.

```typescript
const response = await container.fetch(request);
const apiResponse = await container.fetch(
  new Request("http://container/api/data"),
);
```

**Parameters:**

- `request`: `Request` - The HTTP request to forward

**Returns:** `Promise<Response>`

### startAndWaitForPorts()

Start the container and wait for it to be ready.

```typescript
await container.startAndWaitForPorts();
// Container is now running and accepting requests
```

**Returns:** `Promise<void>`

### stop()

Gracefully stop the container (sends SIGTERM).

```typescript
await container.stop();
```

**Returns:** `Promise<void>`

### destroy()

Forcefully terminate the container (sends SIGKILL).

```typescript
await container.destroy();
```

**Returns:** `Promise<void>`

### signal(signal)

Send a signal to the container process.

```typescript
await container.signal("SIGTERM");
await container.signal("SIGKILL");
await container.signal("SIGUSR1");
```

**Parameters:**

- `signal`: `string` - Signal name (e.g., "SIGTERM", "SIGKILL", "SIGUSR1")

**Returns:** `Promise<void>`

### getTcpPort(port)

Get a TCP socket connection to a specific port.

```typescript
const socket = await container.getTcpPort(5432);
// Use socket for TCP communication
```

**Parameters:**

- `port`: `number` - Port number to connect to

**Returns:** `Promise<Socket>`

### monitor()

Stream container status events.

```typescript
const events = container.monitor();
for await (const event of events) {
  console.log("Container event:", event);
}
```

**Returns:** `AsyncIterable<ContainerEvent>`

## Status Hooks

Override these methods to execute code on lifecycle events.

### onStart()

Called when the container starts.

```typescript
export class MyContainer extends Container {
  async onStart() {
    console.log("Container started");
    // Initialize resources
    // Send notifications
    // Update external systems
  }
}
```

### onStop()

Called when the container stops.

```typescript
export class MyContainer extends Container {
  async onStop() {
    console.log("Container stopped");
    // Cleanup resources
    // Save state
    // Send notifications
  }
}
```

### onError(error)

Called when the container encounters an error.

```typescript
export class MyContainer extends Container {
  async onError(error: Error) {
    console.error("Container error:", error);
    // Log error
    // Send alerts
    // Attempt recovery
  }
}
```

## Helper Functions

### getContainer(binding, id)

Get a container instance by ID.

```typescript
import { getContainer } from "@cloudflare/containers";

// Get container by unique ID
const container = getContainer(env.MY_CONTAINER, "user-123");
const container = getContainer(env.MY_CONTAINER, crypto.randomUUID());
```

**Parameters:**

- `binding`: `DurableObjectNamespace` - The container binding from env
- `id`: `string` - Unique identifier for this container instance

**Returns:** `ContainerInstance`

### getRandom(binding, count)

Get a random container from a pool (temporary helper).

```typescript
import { getRandom } from "@cloudflare/containers";

// Route to one of 5 instances randomly
const container = getRandom(env.MY_CONTAINER, 5);
```

**Parameters:**

- `binding`: `DurableObjectNamespace` - The container binding from env
- `count`: `number` - Number of instances in the pool

**Returns:** `ContainerInstance`

**Note:** This is a temporary solution. Will be replaced by autoscaling.

### getByName(name)

Get a container stub by name directly from the binding. This is the recommended approach for most use cases.

```typescript
// Using binding directly - returns stub immediately
const container = env.MY_CONTAINER.getByName("main-instance");
return container.fetch(request);

// Common pattern in fetch handler
export default {
  async fetch(request: Request, env: Env) {
    return env.MY_CONTAINER.getByName("hello").fetch(request);
  },
};
```

**Parameters:**

- `name`: `string` - A string name that uniquely identifies the container instance. The same name always routes to the same instance.

**Returns:** `DurableObjectStub` - A stub that can be used to invoke methods on the container. The stub is returned immediately, before a connection is established, allowing requests to be sent without waiting for a network round trip.

**Notes:**

- This method is available directly on the `DurableObjectNamespace` binding (e.g., `env.MY_CONTAINER`)
- The stub has a `name` property that returns the name used to create it
- Prefer this over `getContainer()` when you don't need the helper's additional functionality

## Durable Object Interface

For advanced use cases, you can access the underlying Durable Object API.

### ctx.container

Access container controls from within the Durable Object.

```typescript
export class MyContainer extends Container {
  async someMethod() {
    // Check if container is running
    const isRunning = this.ctx.container.running;

    // Start container
    await this.ctx.container.start();

    // Get TCP port
    const socket = await this.ctx.container.getTcpPort(8080);

    // Send signal
    await this.ctx.container.signal("SIGTERM");

    // Destroy container
    await this.ctx.container.destroy();
  }
}
```

### ctx.container Properties

| Property  | Type    | Description                            |
| --------- | ------- | -------------------------------------- |
| `running` | boolean | Whether container is currently running |

### ctx.container Methods

| Method             | Description                        |
| ------------------ | ---------------------------------- |
| `start()`          | Start the container                |
| `destroy()`        | Forcefully terminate the container |
| `signal(sig)`      | Send a signal to the container     |
| `getTcpPort(port)` | Get TCP socket to port             |
| `monitor()`        | Stream status events               |

## Durable Object Storage

Since Container extends DurableObject, you have full access to storage APIs.

### SQLite Storage

```typescript
export class MyContainer extends Container {
  async saveState(data: any) {
    await this.ctx.storage.sql.exec(
      "INSERT INTO state (key, value) VALUES (?, ?)",
      "mykey",
      JSON.stringify(data),
    );
  }

  async loadState(key: string) {
    const result = await this.ctx.storage.sql.exec(
      "SELECT value FROM state WHERE key = ?",
      key,
    );
    return result.rows[0]?.value;
  }
}
```

### Key-Value Storage

```typescript
export class MyContainer extends Container {
  async saveData() {
    await this.ctx.storage.put("lastRun", Date.now());
    await this.ctx.storage.put("config", { debug: true });
  }

  async loadData() {
    const lastRun = await this.ctx.storage.get("lastRun");
    const config = await this.ctx.storage.get("config");
    return { lastRun, config };
  }
}
```

## Complete Example

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
    // Could send to error tracking service
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const sessionId = url.searchParams.get("session") || "default";

    const container = getContainer(env.MY_CONTAINER, sessionId);

    // Forward request to container
    return container.fetch(request);
  },
};
```

## TypeScript Types

### ContainerInstance

```typescript
interface ContainerInstance {
  fetch(request: Request): Promise<Response>;
  startAndWaitForPorts(): Promise<void>;
  stop(): Promise<void>;
  destroy(): Promise<void>;
  signal(signal: string): Promise<void>;
  getTcpPort(port: number): Promise<Socket>;
  monitor(): AsyncIterable<ContainerEvent>;
}
```

### ContainerEvent

```typescript
interface ContainerEvent {
  type: "start" | "stop" | "error";
  timestamp: number;
  error?: Error;
}
```

### Env Type Definition

```typescript
interface Env {
  MY_CONTAINER: DurableObjectNamespace<MyContainer>;
  // Add your other bindings
  API_KEY: string;
  KV_NAMESPACE: KVNamespace;
}
```
