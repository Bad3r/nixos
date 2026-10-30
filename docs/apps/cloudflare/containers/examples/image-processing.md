# Cloudflare Containers example: image processing

An image resize service that runs ImageMagick in a container.

## Dockerfile

```dockerfile
FROM alpine:3.20

# Install ImageMagick and Node.js
RUN apk add --no-cache imagemagick nodejs npm

WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .

EXPOSE 8080
CMD ["node", "server.js"]
```

## Server (server.js)

```javascript
const http = require("http");
const { spawn } = require("child_process");
const { randomUUID } = require("crypto");
const fs = require("fs").promises;
const os = require("os");
const path = require("path");

const MAX_DIMENSION = 4096;

function parseDimension(value, fallback) {
  const parsed = Number.parseInt(String(value ?? fallback), 10);
  if (!Number.isFinite(parsed) || parsed < 1 || parsed > MAX_DIMENSION) {
    throw new Error(
      `Dimensions must be an integer between 1 and ${MAX_DIMENSION}`,
    );
  }
  return parsed;
}

function runConvert(inputPath, outputPath, width, height) {
  return new Promise((resolve, reject) => {
    const proc = spawn("convert", [
      inputPath,
      "-resize",
      `${width}x${height}`,
      outputPath,
    ]);
    let stderr = "";

    proc.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    proc.on("error", reject);
    proc.on("close", (code) => {
      if (code === 0) {
        resolve();
        return;
      }
      reject(new Error(`convert failed (${code}): ${stderr.trim()}`));
    });
  });
}

const server = http.createServer(async (req, res) => {
  if (req.method !== "POST" || req.url !== "/resize") {
    res.writeHead(404);
    res.end("Not Found");
    return;
  }

  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const imageBuffer = Buffer.concat(chunks);

  let width;
  let height;
  try {
    width = parseDimension(req.headers["x-width"], 200);
    height = parseDimension(req.headers["x-height"], 200);
  } catch (error) {
    res.writeHead(400, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: error.message }));
    return;
  }

  const requestId = randomUUID();
  const inputPath = path.join(os.tmpdir(), `input-${requestId}.jpg`);
  const outputPath = path.join(os.tmpdir(), `output-${requestId}.jpg`);

  try {
    await fs.writeFile(inputPath, imageBuffer);
    await runConvert(inputPath, outputPath, width, height);
    const result = await fs.readFile(outputPath);
    res.writeHead(200, { "Content-Type": "image/jpeg" });
    res.end(result);
  } catch (error) {
    res.writeHead(500, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Image processing failed" }));
  } finally {
    await Promise.allSettled([fs.unlink(inputPath), fs.unlink(outputPath)]);
  }
});

server.listen(8080);
```

## Worker (src/index.ts)

The `IMAGE_PROCESSOR` binding needs the `ImageProcessor` container, Durable Object binding, and migration entries in [`wrangler.jsonc`](../configuration.md#wrangler-configuration).

```typescript
import { Container, getContainer } from "@cloudflare/containers";

export class ImageProcessor extends Container {
  defaultPort = 8080;
  sleepAfter = "5m";
}

export default {
  async fetch(request: Request, env: Env) {
    const processor = getContainer(env.IMAGE_PROCESSOR, "main");
    return processor.fetch(request);
  },
};
```
