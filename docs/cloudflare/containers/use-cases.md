# Cloudflare Containers Use Cases & Examples

## When to Use Containers

### Containers Are Best For

| Use Case                         | Why Containers                                     |
| -------------------------------- | -------------------------------------------------- |
| **Any language runtime**         | Python, Go, Rust, PHP, Ruby, Java                  |
| **Resource-intensive workloads** | ML inference, video processing, image manipulation |
| **Legacy application migration** | Existing Docker images without rewrites            |
| **Per-user isolation**           | Code sandboxes, dev environments                   |
| **Long-running processes**       | Batch jobs, background workers                     |
| **Full filesystem access**       | Apps requiring temp files, caches                  |
| **Custom system dependencies**   | FFmpeg, ImageMagick, native libraries              |

### Workers Are Better For

| Use Case                   | Why Workers                  |
| -------------------------- | ---------------------------- |
| **Low latency APIs**       | Instant cold starts          |
| **Edge logic**             | Auth, routing, transforms    |
| **Lightweight processing** | JSON manipulation, redirects |
| **High request volume**    | Automatic scaling            |
| **Cost-sensitive**         | Pay per request, not runtime |

## Example 1: Static Frontend + Container Backend

A React frontend served by Pages with a Python API backend.

### Project Structure

```
my-app/
├── frontend/
│   ├── src/
│   └── package.json
├── backend/
│   ├── app.py
│   ├── requirements.txt
│   └── Dockerfile
├── src/
│   └── index.ts
└── wrangler.jsonc
```

### Backend Dockerfile

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
```

### Backend API (app.py)

```python
from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI()

class Item(BaseModel):
    name: str
    value: float

@app.get("/api/health")
async def health():
    return {"status": "healthy"}

@app.post("/api/process")
async def process(item: Item):
    # Heavy processing here
    result = item.value * 2
    return {"name": item.name, "result": result}
```

### Worker (src/index.ts)

```typescript
import { Container, getContainer } from "@cloudflare/containers";

export class Backend extends Container {
  defaultPort = 8080;
  sleepAfter = "10m";
}

export default {
  async fetch(request: Request, env: Env) {
    const url = new URL(request.url);

    // Route API requests to container
    if (url.pathname.startsWith("/api/")) {
      const backend = getContainer(env.BACKEND, "main");
      return backend.fetch(request);
    }

    // Serve static assets from Pages (or return 404)
    return new Response("Not Found", { status: 404 });
  },
};
```

### wrangler.jsonc

```jsonc
{
  "name": "fullstack-app",
  "main": "src/index.ts",
  "compatibility_date": "2026-02-04",
  "containers": [
    {
      "class_name": "Backend",
      "image": "./backend/Dockerfile",
      "instance_type": "basic",
    },
  ],
  "durable_objects": {
    "bindings": [{ "class_name": "Backend", "name": "BACKEND" }],
  },
  "migrations": [{ "new_sqlite_classes": ["Backend"], "tag": "v1" }],
}
```

## Example 2: Cron-Triggered Batch Job

Run a data processing job on a schedule.

### Dockerfile

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Job script, not a long-running server
CMD ["python", "job.py"]
```

### Job Script (job.py)

```python
import os
import json
import requests
from datetime import datetime

def run_job():
    print(f"Job started at {datetime.now()}")

    # Fetch data from external API
    response = requests.get(os.environ['DATA_SOURCE_URL'])
    data = response.json()

    # Process data
    processed = [
        {"id": item["id"], "value": item["value"] * 2}
        for item in data
    ]

    # Store results (would use R2 or external storage)
    print(f"Processed {len(processed)} items")

    # Signal completion
    print("Job completed successfully")

if __name__ == "__main__":
    run_job()
```

### Worker (src/index.ts)

```typescript
import { Container, getContainer } from "@cloudflare/containers";

export class BatchJob extends Container {
  sleepAfter = "1m"; // Short timeout after job completes

  envVars = {
    DATA_SOURCE_URL: this.env.DATA_SOURCE_URL,
  };
}

export default {
  // Cron trigger handler
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext) {
    console.log(`Cron triggered at ${event.scheduledTime}`);

    const job = getContainer(env.BATCH_JOB, "daily-job");

    // Start the batch container on schedule
    await job.start();

    // Job runs its CMD and exits
    // Container will sleep after 1 minute
  },

  // Also allow manual trigger via HTTP
  async fetch(request: Request, env: Env) {
    if (
      request.method === "POST" &&
      new URL(request.url).pathname === "/trigger"
    ) {
      const job = getContainer(env.BATCH_JOB, "manual-job");
      await job.start();
      return new Response("Job triggered");
    }
    return new Response("POST /trigger to run job", { status: 400 });
  },
};
```

### wrangler.jsonc

```jsonc
{
  "name": "batch-processor",
  "main": "src/index.ts",
  "triggers": {
    "crons": ["0 2 * * *"], // Run at 2 AM daily
  },
  "containers": [
    {
      "class_name": "BatchJob",
      "image": "./Dockerfile",
    },
  ],
  "durable_objects": {
    "bindings": [{ "class_name": "BatchJob", "name": "BATCH_JOB" }],
  },
  "migrations": [{ "new_sqlite_classes": ["BatchJob"], "tag": "v1" }],
  "vars": {
    "DATA_SOURCE_URL": "https://api.example.com/data",
  },
}
```

## Example 3: Per-User Code Sandbox

Isolated execution environment for each user.

### Dockerfile

```dockerfile
FROM node:20-alpine

# Install useful tools
RUN apk add --no-cache git python3

WORKDIR /sandbox

# Create non-root user for security
RUN adduser -D sandboxuser
USER sandboxuser

EXPOSE 8080

# Simple HTTP server to receive and execute code
CMD ["node", "executor.js"]
```

### Executor (executor.js)

```javascript
const http = require("http");
const { spawn } = require("child_process");
const fs = require("fs").promises;
const path = require("path");

const server = http.createServer(async (req, res) => {
  if (req.method === "POST" && req.url === "/execute") {
    let body = "";
    for await (const chunk of req) body += chunk;

    const { language, code, timeout = 5000 } = JSON.parse(body);

    try {
      const result = await executeCode(language, code, timeout);
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify(result));
    } catch (error) {
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: error.message }));
    }
  } else {
    res.writeHead(404);
    res.end("Not Found");
  }
});

async function executeCode(language, code, timeout) {
  const tempFile = `/tmp/code_${Date.now()}`;

  let cmd, args, ext;
  switch (language) {
    case "javascript":
      ext = ".js";
      cmd = "node";
      args = [tempFile + ext];
      break;
    case "python":
      ext = ".py";
      cmd = "python3";
      args = [tempFile + ext];
      break;
    default:
      throw new Error(`Unsupported language: ${language}`);
  }

  await fs.writeFile(tempFile + ext, code);

  return new Promise((resolve, reject) => {
    const proc = spawn(cmd, args, { timeout });

    let stdout = "",
      stderr = "";
    proc.stdout.on("data", (data) => (stdout += data));
    proc.stderr.on("data", (data) => (stderr += data));

    proc.on("close", (exitCode) => {
      fs.unlink(tempFile + ext).catch(() => {});
      resolve({ stdout, stderr, exitCode });
    });

    proc.on("error", reject);
  });
}

server.listen(8080);
console.log("Sandbox executor running on port 8080");
```

### Worker (src/index.ts)

```typescript
import { Container, getContainer } from "@cloudflare/containers";

export class Sandbox extends Container {
  defaultPort = 8080;
  sleepAfter = "5m"; // Keep sandbox warm for interactive use
}

export default {
  async fetch(request: Request, env: Env) {
    const url = new URL(request.url);

    // Extract user ID for isolation
    const userId = request.headers.get("X-User-ID");
    if (!userId) {
      return new Response("X-User-ID header required", { status: 401 });
    }

    // Each user gets their own container instance
    const sandbox = getContainer(env.SANDBOX, `user-${userId}`);

    if (url.pathname === "/execute" && request.method === "POST") {
      // Forward execution request to user's sandbox
      return sandbox.fetch(request);
    }

    return new Response("POST /execute with code", { status: 400 });
  },
};
```

### Usage

```bash
curl -X POST https://sandbox.example.com/execute \
  -H "X-User-ID: user123" \
  -H "Content-Type: application/json" \
  -d '{
    "language": "python",
    "code": "print(sum(range(100)))"
  }'

# Response: {"stdout": "4950\n", "stderr": "", "exitCode": 0}
```

## Example 4: WebSocket Chat Server

Real-time chat using WebSockets.

### Dockerfile

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 8080
CMD ["node", "chat-server.js"]
```

### Chat Server (chat-server.js)

```javascript
const WebSocket = require("ws");
const http = require("http");

const server = http.createServer();
const wss = new WebSocket.Server({ server });

const rooms = new Map();

wss.on("connection", (ws, req) => {
  const url = new URL(req.url, "http://localhost");
  const room = url.searchParams.get("room") || "default";
  const username = url.searchParams.get("username") || "anonymous";

  // Join room
  if (!rooms.has(room)) {
    rooms.set(room, new Set());
  }
  rooms.get(room).add(ws);

  console.log(`${username} joined ${room}`);

  // Broadcast join
  broadcast(room, { type: "join", username, room });

  ws.on("message", (data) => {
    const message = JSON.parse(data);
    broadcast(room, {
      type: "message",
      username,
      text: message.text,
      timestamp: Date.now(),
    });
  });

  ws.on("close", () => {
    rooms.get(room).delete(ws);
    broadcast(room, { type: "leave", username, room });
  });
});

function broadcast(room, message) {
  const clients = rooms.get(room);
  if (clients) {
    const data = JSON.stringify(message);
    clients.forEach((client) => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(data);
      }
    });
  }
}

server.listen(8080);
console.log("Chat server running on port 8080");
```

### Worker (src/index.ts)

```typescript
import { Container, getContainer } from "@cloudflare/containers";

export class ChatServer extends Container {
  defaultPort = 8080;
  sleepAfter = "30m"; // Keep alive for active chats
}

export default {
  async fetch(request: Request, env: Env) {
    const url = new URL(request.url);
    const room = url.searchParams.get("room") || "default";

    // Validate WebSocket upgrade
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("WebSocket required", { status: 426 });
    }

    // Route to room-specific container
    const chatServer = getContainer(env.CHAT_SERVER, `room-${room}`);
    return chatServer.fetch(request);
  },
};
```

## Example 5: ML Inference Service

Run a machine learning model for inference.

### Dockerfile

```dockerfile
FROM python:3.11-slim

# Install ML dependencies
RUN pip install --no-cache-dir \
    torch \
    transformers \
    fastapi \
    uvicorn

WORKDIR /app
COPY . .

# Download model on build (cached in image)
RUN python -c "from transformers import pipeline; pipeline('sentiment-analysis')"

EXPOSE 8080
CMD ["uvicorn", "inference:app", "--host", "0.0.0.0", "--port", "8080"]
```

### Inference API (inference.py)

```python
from fastapi import FastAPI
from pydantic import BaseModel
from transformers import pipeline
import torch

app = FastAPI()

# Load model once at startup
classifier = pipeline(
    "sentiment-analysis",
    device=0 if torch.cuda.is_available() else -1
)

class TextInput(BaseModel):
    text: str

class BatchInput(BaseModel):
    texts: list[str]

@app.post("/predict")
async def predict(input: TextInput):
    result = classifier(input.text)[0]
    return {
        "label": result["label"],
        "score": result["score"]
    }

@app.post("/batch")
async def batch_predict(input: BatchInput):
    results = classifier(input.texts)
    return {"results": results}

@app.get("/health")
async def health():
    return {"status": "ready", "model": "sentiment-analysis"}
```

### Worker (src/index.ts)

```typescript
import { Container, getContainer } from "@cloudflare/containers";

export class MLService extends Container {
  defaultPort = 8080;
  sleepAfter = "15m"; // Keep model loaded
}

export default {
  async fetch(request: Request, env: Env) {
    const ml = getContainer(env.ML_SERVICE, "inference");
    return ml.fetch(request);
  },
};
```

### wrangler.jsonc

```jsonc
{
  "name": "ml-inference",
  "main": "src/index.ts",
  "containers": [
    {
      "class_name": "MLService",
      "image": "./Dockerfile",
      "instance_type": "standard-2", // More memory for ML
    },
  ],
  "durable_objects": {
    "bindings": [{ "class_name": "MLService", "name": "ML_SERVICE" }],
  },
  "migrations": [{ "new_sqlite_classes": ["MLService"], "tag": "v1" }],
}
```

## Example 6: Image Processing Service

Process and transform images using ImageMagick.

### Dockerfile

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

### Server (server.js)

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

### Worker (src/index.ts)

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

## Best Practices Summary

### 1. Choose the Right Instance Type

```typescript
// Light workloads
class LightContainer extends Container {
  // Use default (basic) or lite
}

// Memory-intensive
class MLContainer extends Container {
  // Configure in wrangler.jsonc: "instance_type": "standard-2"
}
```

### 2. Optimize Cold Starts

```dockerfile
# Use small base images
FROM alpine:3.20  # Good
FROM ubuntu:22.04  # Larger, slower

# Multi-stage builds
FROM node:20 AS builder
RUN npm run build

FROM node:20-alpine
COPY --from=builder /app/dist ./dist
```

### 3. Handle Graceful Shutdown

```javascript
process.on("SIGTERM", async () => {
  await server.close();
  await db.close();
  process.exit(0);
});
```

### 4. Use Appropriate Storage

```typescript
// Temp data: ephemeral disk
fs.writeFileSync("/tmp/cache.json", data);

// Persistent state: DO storage
await this.ctx.storage.put("state", data);

// Large files: R2
// Mount R2 bucket via FUSE
```

### 5. Validate Requests in Worker

```typescript
export default {
  async fetch(request: Request, env: Env) {
    // Validate before incurring container cost
    const auth = request.headers.get("Authorization");
    if (!isValidAuth(auth)) {
      return new Response("Unauthorized", { status: 401 });
    }
    return getContainer(env.MY_CONTAINER, "main").fetch(request);
  },
};
```
