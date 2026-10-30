# Cloudflare Containers images

A container's `image` key in the Wrangler configuration names either a local Dockerfile or a pre-built image in a supported registry.

## Distribution

1. **Build**: Wrangler builds the image locally through Docker.
2. **Push**: the image goes to the Cloudflare Registry, which is backed by R2.
3. **Distribute**: the image is pre-fetched to global locations.
4. **Pre-warm**: instances are pre-scheduled for quick starts.

```text
+----------+    +-------------+    +------------------+
|  Docker  |--->|  Cloudflare |--->|  Global Edge     |
|  Build   |    |  Registry   |    |  Pre-fetch       |
+----------+    |  (R2-backed)|    |  Locations       |
                +-------------+    +------------------+
```

## Registry sources

| Source                          | Description                           |
| ------------------------------- | ------------------------------------- |
| `./Dockerfile`                  | Built locally, pushed to the registry |
| `registry.cloudflare.com/...`   | Pre-built in Cloudflare Registry      |
| `*.dkr.ecr.*.amazonaws.com/...` | Amazon ECR, needs credentials         |

A Cloudflare Registry image is referenced by its full URL:

```jsonc
{
  "containers": [
    {
      "image": "registry.cloudflare.com/my-account/my-image:v1.0",
    },
  ],
}
```

### Amazon ECR

Configure the registry credentials once:

```bash
npx wrangler containers registries configure \
  123456789012.dkr.ecr.us-east-1.amazonaws.com \
  --aws-access-key-id=AKIAIOSFODNN7EXAMPLE
```

Then reference the image:

```jsonc
{
  "containers": [
    {
      "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-repo:tag",
    },
  ],
}
```

## Dockerfiles

The port the image exposes must match `defaultPort` in the Container class.
Images must target `linux/amd64`, and a small image shortens [cold starts](./cold-starts.md).

### Node.js

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 8080
CMD ["node", "server.js"]
```

### Multi-stage build

```dockerfile
# Build stage
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Production stage
FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
EXPOSE 8080
CMD ["node", "dist/server.js"]
```

### Python

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8080
CMD ["python", "app.py"]
```

### Go

```dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.* ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o server .

FROM alpine:3.19
COPY --from=builder /app/server /server
EXPOSE 8080
CMD ["/server"]
```
