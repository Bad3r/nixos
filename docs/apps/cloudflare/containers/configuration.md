# Cloudflare Containers configuration

A Containers project is a Worker whose Wrangler configuration declares a container class, its Durable Object binding, and a migration.

## Prerequisites

- The Workers Paid plan.
- A running Docker daemon for local image builds.

```bash
docker info
```

When `docker info` fails, start Docker Desktop or run `sudo systemctl start docker`.

## Project setup

Start from the template, or add the packages to an empty project:

```bash
npm create cloudflare@latest my-container-app -- --template container
```

```bash
mkdir my-container-app && cd my-container-app
npm init -y
npm install @cloudflare/containers wrangler
```

## Wrangler configuration

```jsonc
// wrangler.jsonc
{
  "name": "my-container-app",
  "main": "src/index.ts",
  "compatibility_date": "2026-02-04",
  "compatibility_flags": ["nodejs_compat"],

  "containers": [
    {
      "class_name": "MyContainer",
      "image": "./Dockerfile",
      "instance_type": "standard-1",
      "max_instances": 10,
      "rollout_step_percentage": 10,
      "rollout_active_grace_period": 300,
    },
  ],

  // Durable Object binding (required)
  "durable_objects": {
    "bindings": [{ "class_name": "MyContainer", "name": "MY_CONTAINER" }],
  },

  // Migration (required for new Durable Object classes)
  "migrations": [{ "new_sqlite_classes": ["MyContainer"], "tag": "v1" }],

  // Optional
  "vars": { "ENVIRONMENT": "production" },
  "triggers": { "crons": ["0 * * * *"] },
}
```

`wrangler.toml` takes the same keys, with `[[containers]]`, `[[durable_objects.bindings]]`, and `[[migrations]]` as array tables.

### Container options

| Option                        | Required | Description                                            |
| ----------------------------- | -------- | ------------------------------------------------------ |
| `class_name`                  | Yes      | Container class in the Worker                          |
| `image`                       | Yes      | Dockerfile path or registry URL                        |
| `instance_type`               | No       | Named or custom type                                   |
| `max_instances`               | No       | `number`: maximum concurrent instances                 |
| `rollout_step_percentage`     | No       | `number`: first rollout step, in percent               |
| `rollout_active_grace_period` | No       | `number`: seconds until an active container can update |

`instance_type` takes a [named type](./README.md#instance-types) or a custom `{ vcpu, memory_mib, disk_mb }` object, and defaults to `lite`.
`image` takes a local Dockerfile path or one of the [registry sources](./images.md#registry-sources).
`rollout_step_percentage` defaults to 10 and sizes the first of the two [rollout steps](./shutdown.md#rollouts).

## TypeScript

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "lib": ["ES2022"],
    "types": ["@cloudflare/workers-types"],
    "strict": true,
    "noEmit": true
  },
  "include": ["src/**/*"]
}
```

The `Env` interface types the bindings the Worker and container class read:

```typescript
// src/types.ts
export interface Env {
  MY_CONTAINER: DurableObjectNamespace<MyContainer>;
  API_KEY: string;
  LOG_LEVEL: string;
}
```

## Project layout

```text
my-container-app/
+-- src/
|   +-- index.ts          # Worker entry point
|   +-- container.ts      # Container class definition
|   +-- types.ts          # TypeScript types
+-- container/
|   +-- Dockerfile        # Container image definition
|   +-- package.json      # Container dependencies
|   +-- server.js         # Container application
+-- wrangler.jsonc        # Wrangler configuration
+-- package.json          # Worker dependencies
+-- tsconfig.json         # TypeScript config
```
