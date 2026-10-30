# Cloudflare Containers deployment

Wrangler builds the image, pushes it, and deploys the Worker; variables and secrets reach the container process through the Container class.

## Environment variables

Static values go under `vars` in `wrangler.jsonc`:

```jsonc
{
  "vars": {
    "LOG_LEVEL": "info",
    "API_URL": "https://api.example.com",
  },
}
```

### Secrets

Set secrets before the deploy that needs them:

```bash
npx wrangler secret put API_KEY
npx wrangler secret list
npx wrangler secret delete API_KEY
```

### Local values

Local development reads `.dev.vars`, which stays out of git:

```bash
# .dev.vars
API_KEY=your-dev-api-key
DATABASE_URL=postgres://localhost/dev
```

### Passing values to the container

Worker variables and secrets reach the container process through `envVars`:

```typescript
import { Container } from "@cloudflare/containers";

export class MyContainer extends Container {
  defaultPort = 8080;

  envVars = {
    LOG_LEVEL: this.env.LOG_LEVEL,
    API_KEY: this.env.API_KEY,
    CUSTOM_VAR: "hardcoded-value",
  };
}
```

## Deploy

```bash
npx wrangler deploy
```

A deploy replaces running containers in [rollout steps](./shutdown.md#rollouts).

## Local development

```bash
npx wrangler dev
```

Local development needs a running Docker daemon and builds the container locally.
It behaves mostly like production.

The Vite plugin is an alternative entry point:

```typescript
// vite.config.ts
import { defineConfig } from "vite";
import { cloudflare } from "@cloudflare/vite-plugin";

export default defineConfig({
  plugins: [cloudflare()],
});
```

The Vite plugin handles registry URLs poorly, so the `image` key points at a Dockerfile path when it is in use.

## Wrangler commands

### Container images

```bash
# Build an image
npx wrangler containers build -t my-image:tag .

# Build and push without deploying the Worker
npx wrangler containers build -p -t my-image:tag .

# Push an existing image
npx wrangler containers push my-image:tag

# List and delete images
npx wrangler containers images list
npx wrangler containers images delete my-image:tag

# Configure an external registry
npx wrangler containers registries configure <registry-url>
```

### Worker

```bash
# Tail logs
npx wrangler tail

# View deployments
npx wrangler deployments list
```
