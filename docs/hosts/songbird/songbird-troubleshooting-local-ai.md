# Songbird troubleshooting: local AI

- [songbird-runbook-local-ai.md](songbird-runbook-local-ai.md)

## llama-cpp exits with option not recognized in preset

llama-server rejects every preset key that names no argument, so one misspelled key stops the router at startup.

```sh
journalctl -u llama-cpp -b -g 'not recognized'
```

Correct or remove the key in `llamaModels` in [services.nix](../../../modules/hosts/songbird/services.nix), using a long argument name without dashes, then switch.

## Requests get HTTP 401

The request carries no key or another key than `/run/secrets/llama-cpp/api-key`, which the service reads once at start.

```sh
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $(cat /run/secrets/llama-cpp/api-key)" http://127.0.0.1:10100/v1/models
```

When that prints `200`, copy the key into the client again; otherwise run `sudo systemctl restart llama-cpp` so the service rereads the rendered secret.

## Requests get HTTP 400 for a model

The router serves only preset sections and models already in its cache, and answers 400 for any other model name.

```sh
curl -s -H "Authorization: Bearer $(cat /run/secrets/llama-cpp/api-key)" http://127.0.0.1:10100/v1/models | jq -r '.data[].id'
```

Request a listed name, or add the model as [songbird-runbook-local-ai.md](songbird-runbook-local-ai.md#switch-the-served-model) describes.

## llama.cpp fails with cudaMalloc failed: out of memory

The weights, the KV cache for the requested context, and the compute buffers exceed free VRAM, most often because another engine still holds a model.

```sh
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv
```

Stop the other engine, then lower `ctx-size` or move experts to RAM with `n-cpu-moe` in the model's `llamaModels` entry.

## llama-server decodes far slower than llama-bench

The default `--fit on` keeps a VRAM safety margin, so it moves expert tensors to RAM whenever the requested context and slots do not fit beside the weights.

```sh
journalctl -u llama-cpp -b -g 'tensor overrides to CPU'
```

Lower `ctx-size` in the model's `llamaModels` entry; when the model then fits, add `fit = "off"` to keep every tensor on the GPU.

## codex exec waits at Reading additional input from stdin

`codex exec` appends standard input to the prompt when stdin is not a terminal, so a script or agent shell leaves it waiting forever.

```sh
codex exec --profile local --skip-git-repo-check '<prompt>' < /dev/null
```

Close stdin with `< /dev/null` on every non-interactive run.
