# Cloudflare Containers R2 mount

A container can mount an R2 bucket as a filesystem through a FUSE adapter such as tigrisfs, which gives it persistent file storage beyond the ephemeral disk.

## Dockerfile

The image installs FUSE and tigrisfs, and a startup script mounts the bucket before running the command:

```dockerfile
FROM alpine:3.20

RUN apk add --no-cache \
    ca-certificates fuse curl bash

# tigrisfs, an R2-compatible FUSE adapter
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then ARCH="amd64"; fi && \
    VERSION=$(curl -s https://api.github.com/repos/tigrisdata/tigrisfs/releases/latest | grep tag_name | cut -d'"' -f4) && \
    curl -L "https://github.com/tigrisdata/tigrisfs/releases/download/${VERSION}/tigrisfs_Linux_${ARCH}.tar.gz" | tar xz -C /usr/local/bin

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

A read-only mount is faster and safer when the container only reads:

```bash
tigrisfs --endpoint "${R2_ENDPOINT}" -o ro -f "${R2_BUCKET_NAME}" /mnt/r2 &
```

## Container class

The class passes the bucket and credentials to the startup script:

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

```jsonc
// wrangler.jsonc
{
  "vars": {
    "R2_BUCKET": "my-bucket",
    "CF_ACCOUNT_ID": "your-account-id",
  },
  // R2_ACCESS_KEY and R2_SECRET_KEY are secrets
}
```

## Credentials

1. Open the [R2 dashboard](https://dash.cloudflare.com/?to=/:account/r2/overview).
2. Create an R2 API token.
3. Store its Access Key ID as `R2_ACCESS_KEY` and its Secret Access Key as `R2_SECRET_KEY`:

```bash
npx wrangler secret put R2_ACCESS_KEY
npx wrangler secret put R2_SECRET_KEY
```

## Performance

Object storage is not a POSIX-compatible filesystem and does not perform like a native SSD.

| Operation           | Performance | Cause                     |
| ------------------- | ----------- | ------------------------- |
| Sequential read     | Good        | Streams large files       |
| Sequential write    | Good        | Uploads new files         |
| Random read         | Slow        | Many small reads          |
| Random write        | Very slow   | Object storage limitation |
| Metadata operations | Slow        | Listing and stat calls    |

The mount suits large files such as images, videos, and documents, read-heavy workloads, files shared between instances, and bootstrap data.
It does not suit database files such as SQLite, frequent small writes, applications that need POSIX guarantees, or latency-sensitive operations.
