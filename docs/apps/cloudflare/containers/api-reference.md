# Cloudflare Containers API reference

The `@cloudflare/containers` package exports the `Container` class, which extends `DurableObject`, and helpers that return container instances from a binding.
A container instance exposes [methods](./api-methods.md) for requests and control, and calls the [status hooks](./api-hooks.md) a subclass overrides.

## Container class

```typescript
import { Container } from "@cloudflare/containers";

export class MyContainer extends Container {
  // Port the container listens on
  defaultPort = 8080;

  // Sleep after 10 minutes of inactivity
  sleepAfter = "10m";

  // Environment for the container process
  envVars = {
    NODE_ENV: "production",
    API_KEY: this.env.API_KEY,
    LOG_LEVEL: "info",
  };
}
```

### Properties

| Property      | Type   | Required | Description                   |
| ------------- | ------ | -------- | ----------------------------- |
| `defaultPort` | number | Yes      | Port the container listens on |
| `sleepAfter`  | string | No       | Inactivity timeout            |
| `envVars`     | object | No       | Environment for the process   |

### Duration format

`sleepAfter` and other duration properties take a number with a unit suffix:

| Unit    | Example | Duration   |
| ------- | ------- | ---------- |
| Seconds | `"30s"` | 30 seconds |
| Minutes | `"10m"` | 10 minutes |
| Hours   | `"2h"`  | 2 hours    |
| Days    | `"1d"`  | 1 day      |

## Helper functions

### getContainer(binding, id)

Returns the container instance for an ID.

```typescript
import { getContainer } from "@cloudflare/containers";

const container = getContainer(env.MY_CONTAINER, "user-123");
const ephemeral = getContainer(env.MY_CONTAINER, crypto.randomUUID());
```

- `binding`: `DurableObjectNamespace`, the container binding from `env`.
- `id`: `string`, the unique identifier for this container instance.

It returns a `ContainerInstance` ([type](./api-methods.md#containerinstance)).

### getRandom(binding, count)

Returns a random container from a pool of `count` instances.

```typescript
import { getRandom } from "@cloudflare/containers";

// Route to one of 5 instances
const container = getRandom(env.MY_CONTAINER, 5);
```

- `binding`: `DurableObjectNamespace`, the container binding from `env`.
- `count`: `number`, the number of instances in the pool.

It returns a `ContainerInstance`.

### getByName(name)

Returns a container stub by name, directly from the binding; it suits most callers.

```typescript
const container = env.MY_CONTAINER.getByName("main-instance");
return container.fetch(request);

// Common pattern in a fetch handler
export default {
  async fetch(request: Request, env: Env) {
    return env.MY_CONTAINER.getByName("hello").fetch(request);
  },
};
```

- `name`: `string`, which uniquely identifies the instance; the same name always routes to the same instance.

It returns a `DurableObjectStub` that invokes methods on the container.
The stub is returned immediately, before a connection exists, so requests go out without waiting for a network round trip.
The stub's `name` property returns the name it was created with.
`getByName` lives on the `DurableObjectNamespace` binding itself, such as `env.MY_CONTAINER`, and is preferred over `getContainer()` unless the helper's extra functionality is needed.
