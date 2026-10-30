# Cloudflare Containers example: ML inference

A sentiment-analysis model served from a container, with the model downloaded at build time so it is cached in the image.

## Dockerfile

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

## Inference API (inference.py)

```python
from fastapi import FastAPI
from pydantic import BaseModel
from transformers import pipeline
import torch

app = FastAPI()

# Load model once at startup
classifier = pipeline("sentiment-analysis", device=0 if torch.cuda.is_available() else -1)


class TextInput(BaseModel):
    text: str


class BatchInput(BaseModel):
    texts: list[str]


@app.post("/predict")
async def predict(input: TextInput):
    result = classifier(input.text)[0]
    return {"label": result["label"], "score": result["score"]}


@app.post("/batch")
async def batch_predict(input: BatchInput):
    results = classifier(input.texts)
    return {"results": results}


@app.get("/health")
async def health():
    return {"status": "ready", "model": "sentiment-analysis"}
```

## Worker (src/index.ts)

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

## wrangler.jsonc

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
