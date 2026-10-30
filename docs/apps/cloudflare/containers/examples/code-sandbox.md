# Cloudflare Containers example: code sandbox

Each user gets an isolated container that executes submitted JavaScript or Python code.

## Dockerfile

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

## Executor (executor.js)

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

## Worker (src/index.ts)

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

## Usage

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
