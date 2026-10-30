# Cloudflare Containers API methods

A container instance from [`getContainer` or `getRandom`](./api-reference.md#helper-functions) forwards requests to the container and controls its process.

## ContainerInstance

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

### fetch(request)

Forwards an HTTP request to the container.

```typescript
const response = await container.fetch(request);
const apiResponse = await container.fetch(
  new Request("http://container/api/data"),
);
```

### startAndWaitForPorts()

Starts the container and resolves once it accepts requests.

```typescript
await container.startAndWaitForPorts();
```

### stop() and destroy()

`stop()` stops the container gracefully with SIGTERM; `destroy()` terminates it with SIGKILL.

```typescript
await container.stop();
await container.destroy();
```

### signal(signal)

Sends a signal, named as a string such as `"SIGTERM"`, `"SIGKILL"`, or `"SIGUSR1"`, to the container process.

```typescript
await container.signal("SIGUSR1");
```

### getTcpPort(port)

Opens a TCP socket to a port in the container.

```typescript
const socket = await container.getTcpPort(5432);
```

### monitor()

Streams container status events.

```typescript
for await (const event of container.monitor()) {
  console.log("Container event:", event);
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

## ctx.container

Inside the Container class, `this.ctx.container` exposes the underlying Durable Object container controls.

```typescript
export class MyContainer extends Container {
  async someMethod() {
    const isRunning = this.ctx.container.running;
    await this.ctx.container.start();
    const socket = await this.ctx.container.getTcpPort(8080);
    await this.ctx.container.signal("SIGTERM");
    await this.ctx.container.destroy();
  }
}
```

| Member             | Description                           |
| ------------------ | ------------------------------------- |
| `running`          | `boolean`: whether the container runs |
| `start()`          | Start the container                   |
| `destroy()`        | Forcefully terminate the container    |
| `signal(sig)`      | Send a signal to the container        |
| `getTcpPort(port)` | Get a TCP socket to a port            |
| `monitor()`        | Stream status events                  |

The class also has the full Durable Object [storage API](./storage.md#durable-object-storage).
