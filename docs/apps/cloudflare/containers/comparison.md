# Cloudflare Containers comparison

Containers trade Workers' instant starts for any runtime and a filesystem, and trade the control of Kubernetes, Lambda, or Fly.io for Durable Object state and Cloudflare's edge.
Workloads map to one or the other by [use case](./use-cases.md).

## Workers

| Aspect         | Workers                   | Containers                       |
| -------------- | ------------------------- | -------------------------------- |
| **Cold start** | Very fast, edge runtime   | Higher, provisioning and warm-up |
| **Runtime**    | V8: JS, TS, WASM          | Any runtime in a container image |
| **CPU time**   | 30 s default, up to 300 s | Long-running process model       |
| **Disk**       | No container filesystem   | 2-20 GB per instance             |

## Kubernetes

| Aspect         | Containers          | Kubernetes                 |
| -------------- | ------------------- | -------------------------- |
| **Setup**      | Zero infrastructure | Cluster management         |
| **Scaling**    | Manual              | Sophisticated autoscaling  |
| **Networking** | HTTP via Worker     | Full network control       |
| **State**      | Built-in DO storage | External state management  |
| **Cost model** | Pay for runtime     | Pay for nodes              |
| **Cold start** | 2-3 seconds         | Varies with pod scheduling |

## AWS Lambda container images

| Aspect                  | Containers      | Lambda containers         |
| ----------------------- | --------------- | ------------------------- |
| **Max runtime**         | Unlimited       | 15 minutes                |
| **Memory**              | Up to 12 GiB    | Up to 10 GB               |
| **State**               | Built-in (DO)   | External (DynamoDB, etc.) |
| **Cold start**          | 2-3 seconds     | Similar or higher         |
| **Networking**          | HTTP via Worker | VPC integration           |
| **Global distribution** | Built-in        | Manual multi-region       |

## Fly.io

| Aspect           | Containers            | Fly.io            |
| ---------------- | --------------------- | ----------------- |
| **Architecture** | DO + VM               | Firecracker VMs   |
| **State**        | Integrated DO storage | Volumes, Postgres |
| **Scaling**      | Manual                | Autoscaling       |
| **Networking**   | HTTP-only ingress     | Full network      |
| **Edge network** | Cloudflare global     | Fly.io regions    |
| **Pricing**      | Per 10 ms of runtime  | Per VM time       |
