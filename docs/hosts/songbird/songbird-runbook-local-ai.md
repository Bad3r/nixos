# Songbird runbook: local AI

- [songbird-local-ai.md](songbird-local-ai.md)
- [songbird-troubleshooting-local-ai.md](songbird-troubleshooting-local-ai.md)

## Run a model in Magnitude

Precondition: `magnitude status` shows `Runtime` as `Ready`, and `nvidia-smi` lists no inference process besides Magnitude's.

1. Choose and download a model as [magnitude.md](../../usage/magnitude.md) describes, then wait until `magnitude models status <model-id>` shows `Installation` as `Installed`.

2. Load the model by its ID:

   ```sh
   magnitude models load <model-id>
   ```

Verification: `magnitude models status <model-id>` shows `Runtime` as `Ready`.

## Use a local model in Claude Code

Precondition: a Magnitude model on songbird shows `Ready`.

1. On songbird, start `claude-local` on a separate config directory:

   ```sh
   CLAUDE_CONFIG_DIR=~/.config/claude-local CLAUDE_LOCAL_MODEL=<model-id> claude-local
   ```

   The separate directory drops the hosted login, hooks, plugins, and MCP servers, which keeps the prompt small for a local model.

Verification: the same command with `-p 'Reply with the word ready'` appended prints `ready`.

## Use a local model in Codex

Precondition: a Magnitude model on songbird shows `Ready`.

1. On songbird, start Codex on the `local` profile that Home Manager generates, naming the loaded model:

   ```sh
   codex -p local -m <model-id>
   ```

Verification: `codex exec -p local -m <model-id> --skip-git-repo-check 'Reply with the word ready' < /dev/null` prints `provider: magnitude` and `ready`.

## Build llama.cpp with CUDA for the RTX 5080

Precondition: run from the repository root, with network access and no decrypted secrets in the worktree.

1. Build the CUDA package from the nixpkgs input pinned by `flake.lock`:

   ```sh
   NIXPKGS_ALLOW_UNFREE=1 nix build --impure --inputs-from path:. nixpkgs#llama-cpp-cuda --out-link ~/.local/state/llama-cpp-cuda
   ```

Verification: `~/.local/state/llama-cpp-cuda/bin/llama-server --list-devices` lists `CUDA0: NVIDIA GeForce RTX 5080`.

## Serve a model to the iPhone

Precondition: `nvidia-smi` lists no inference process, the CUDA build above exists, and the iPhone is on the Mesh.

1. Serve llama-server on songbird's Mesh address (`ip -4 addr show CloudflareWARP`) and a port inside `firewallLocalTcpPortRanges` in `modules/hosts/songbird/policy.nix`, behind a key file:

   ```sh
   install -d -m 700 ~/.config/llama
   [ -s ~/.config/llama/api-key ] || head -c 24 /dev/urandom | base64 >| ~/.config/llama/api-key
   spwnd ~/.local/state/llama-cpp-cuda/bin/llama-server -m <model.gguf> --mmproj <mmproj.gguf> --host <mesh-address> --port <port> --api-key-file ~/.config/llama/api-key
   ```

   `--mmproj` loads the vision projector, the `mmproj` GGUF published beside the model, so the web UI accepts images.

   Never add `--tools`, `--agent`, `--ui-mcp-proxy`, `--mcp-servers-config`, or `--mcp-servers-json` to a server on the Mesh; they expose shell commands, MCP server tools, or a URL proxy.

2. Open `http://<mesh-address>:<port>` in Safari and paste the key into the web UI settings.

Verification, from an enrolled Mesh peer:

- `curl -s -o /dev/null -w '%{http_code}' http://<mesh-address>:<port>/v1/models` prints `401`, and the same request with `-H "Authorization: Bearer <key>"` prints `200`.
- `curl -s -H "Authorization: Bearer <key>" http://<mesh-address>:<port>/props | jq .modalities.vision` prints `true`.

## Free the GPU

Precondition: none.

1. Quit Magnitude Desktop if it is open.

2. Stop the Magnitude service, since any client request loads a model again while it runs, then stop any llama-server started with `spwnd`:

   ```sh
   systemctl --user stop magnitude-server
   systemctl --user stop 'spwn-llama*'
   ```

   `systemctl --user start magnitude-server` brings Magnitude back once the other engine exits.

Verification: `nvidia-smi --query-compute-apps=process_name,used_memory --format=csv` lists no inference process.
