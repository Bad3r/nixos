# Cloudflare Containers example: full-stack app

A React frontend served by Pages with a Python FastAPI backend in a container; the Worker routes `/api/` requests to the backend.

## Project structure

```text
my-app/
+-- frontend/
|   +-- src/
|   +-- package.json
+-- backend/
|   +-- app.py
|   +-- requirements.txt
|   +-- Dockerfile
+-- src/
|   +-- index.ts
+-- wrangler.jsonc
```

## Backend Dockerfile

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
```

## Backend API (app.py)

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

## Worker (src/index.ts)

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

## wrangler.jsonc

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
