# Cloudflare Containers example: batch job

A cron trigger starts a container that runs a data processing job and exits; an HTTP `POST /trigger` starts it on demand.

## Dockerfile

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Job script, not a long-running server
CMD ["python", "job.py"]
```

## Job script (job.py)

```python
import os
import json
import requests
from datetime import datetime


def run_job():
    print(f"Job started at {datetime.now()}")

    # Fetch data from external API
    response = requests.get(os.environ["DATA_SOURCE_URL"])
    data = response.json()

    # Process data
    processed = [{"id": item["id"], "value": item["value"] * 2} for item in data]

    # Store results (would use R2 or external storage)
    print(f"Processed {len(processed)} items")

    # Signal completion
    print("Job completed successfully")


if __name__ == "__main__":
    run_job()
```

## Worker (src/index.ts)

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

## wrangler.jsonc

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
