# Songbird troubleshooting: local AI

- [songbird-runbook-local-ai.md](songbird-runbook-local-ai.md)

## llama.cpp fails with cudaMalloc failed: out of memory

The weights, the KV cache for the requested context, and the compute buffers exceed free VRAM, most often because another engine still holds a model.

```sh
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv
```

Stop the other engine, then quantize the KV cache with `-ctk q8_0 -ctv q8_0`, lower `-c`, or move experts to RAM with `--n-cpu-moe`.

## Magnitude drops its model while another engine runs

Magnitude's scheduler unloads the active model when VRAM runs short, rather than failing requests, so starting llama-server or another GPU engine beside it evicts the model.

```sh
grep -a 'memory pressure' ~/.magnitude/logs/inference.log | tail -n 3
```

Run one engine at a time: free the GPU as in [songbird-runbook-local-ai.md](songbird-runbook-local-ai.md#free-the-gpu) before starting another.

## llama-server decodes far slower than llama-bench

The default `--fit on` keeps a VRAM safety margin, so it moves expert tensors to RAM whenever the requested context and slots do not fit beside the weights.

```sh
journalctl --user -b -u 'spwn-llama*' -g 'tensor overrides to CPU'
```

Start the server with `-np 1 -ctk q8_0 -ctv q8_0` and an explicit `-c`; when the model then fits, add `--fit off -ngl 99` to keep every tensor on the GPU.

## codex exec waits at Reading additional input from stdin

`codex exec` appends standard input to the prompt when stdin is not a terminal, so a script or agent shell leaves it waiting forever.

```sh
codex exec --profile local --skip-git-repo-check '<prompt>' < /dev/null
```

Close stdin with `< /dev/null` on every non-interactive run.
