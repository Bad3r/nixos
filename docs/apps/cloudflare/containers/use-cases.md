# Cloudflare Containers use cases

Containers fit workloads that need a non-JavaScript runtime, more resources, or a filesystem; Workers fit light, latency-sensitive edge logic.

## Containers fit

| Use case                         | Why containers                    |
| -------------------------------- | --------------------------------- |
| **Any language runtime**         | Python, Go, Rust, PHP, Ruby, Java |
| **Resource-intensive workloads** | ML inference, video, images       |
| **Legacy application migration** | Existing images without rewrites  |
| **Per-user isolation**           | Code sandboxes, dev environments  |
| **Long-running processes**       | Batch jobs, background workers    |
| **Full filesystem access**       | Temp files and caches             |
| **Custom system dependencies**   | FFmpeg, ImageMagick, native libs  |

## Workers fit

| Use case                   | Why Workers                  |
| -------------------------- | ---------------------------- |
| **Low latency APIs**       | Instant cold starts          |
| **Edge logic**             | Auth, routing, transforms    |
| **Lightweight processing** | JSON manipulation, redirects |
| **High request volume**    | Automatic scaling            |
| **Cost-sensitive**         | Pay per request, not runtime |

## Examples

| Example                                            | Pattern                              |
| -------------------------------------------------- | ------------------------------------ |
| [Full-stack app](./examples/fullstack.md)          | Pages frontend, Python API container |
| [Batch job](./examples/batch-job.md)               | Cron-triggered job container         |
| [Code sandbox](./examples/code-sandbox.md)         | One isolated container per user      |
| [WebSocket chat](./examples/websocket-chat.md)     | One container per chat room          |
| [ML inference](./examples/ml-inference.md)         | Model cached in the image            |
| [Image processing](./examples/image-processing.md) | ImageMagick resize service           |
