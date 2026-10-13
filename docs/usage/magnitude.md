# Local models with Magnitude

Magnitude runs open models on songbird's GPU and serves them to Claude Code and Codex, on songbird and over Cloudflare Mesh.
[magnitude.nix](../../modules/apps/magnitude.nix) owns the server, and its `client` options set each host's endpoint and default model.
The models fit in one consumer GPU, so they suit private, offline, or quick work rather than the hardest coding tasks.

## Run an agent on a local model

Start Claude Code with every model slot on the local model:

```sh
claude-local
```

Start Codex with the `local` profile:

```sh
codex -p local
```

Both keep the usual settings, hooks, and MCP servers, while plain `claude` and `codex` stay on the cloud models.
Pick another downloaded model per launch:

```sh
CLAUDE_LOCAL_MODEL=<model-id> claude-local
codex -p local -m <model-id>
```

`claude-local --model` moves only the main slot, and Magnitude reloads weights each time two slots ask for different models.
The first request of a session prefills the whole system prompt and tool list, so it is the slowest turn.

## Choose and download models

Run the catalog commands on songbird:

```sh
magnitude catalog recommendations --preference smarter
magnitude catalog pull <model-id>
magnitude models status
```

The catalog lists only models that fit in GPU memory, and Magnitude keeps one model loaded at a time.
`magnitude catalog show <model-id>` reports a model's fit and context size.
A model whose context is smaller than `client.contextWindow` needs that option lowered.

## Manage the service

The `magnitude-server` user service starts with the owner's login session on songbird, and other hosts reach it only while that session runs:

```sh
systemctl --user status magnitude-server
journalctl --user -u magnitude-server
```

Opening Magnitude Desktop ends the service, so start it again after quitting Desktop:

```sh
systemctl --user start magnitude-server
```

`magnitude connections` rewrites the Nix-managed Claude Code and Codex configuration, so leave it unused.

## Fix connection errors

- Connection refused from another host: the service is stopped on songbird, or it started before the switch that enabled Mesh access.
- HTTP 401: the client key is missing or differs from the server's; both hosts read the same sops secret after a switch, and a build without `secrets/magnitude.yaml` warns about the missing key.
- HTTP 421: the request named a host Magnitude does not accept; use `songbird.internal`.

## Fix startup errors

- `Legacy user service is loaded without its verified source file`: a unit named `magnitude.service` is loaded or failed in the user manager, and Magnitude reserves that name for its own startup entry.
  Clear a failed one with `systemctl --user reset-failed magnitude.service`.

[Magnitude documentation](https://docs.magnitude.dev)
