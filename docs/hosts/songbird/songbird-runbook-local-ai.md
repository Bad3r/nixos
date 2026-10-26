# Songbird runbook: local AI

- [songbird-local-ai.md](songbird-local-ai.md)
- [songbird-troubleshooting-local-ai.md](songbird-troubleshooting-local-ai.md)

## Check the llama.cpp service

Precondition: a shell on songbird as the owner, who can read the API key.

1. Show the unit and the log of the router and its model processes:

   ```sh
   systemctl status llama-cpp
   journalctl -u llama-cpp -b
   ```

2. List the models the router serves, with the key and without it:

   ```sh
   curl -s -H "Authorization: Bearer $(cat /run/secrets/llama-cpp/api-key)" http://127.0.0.1:10100/v1/models | jq '.data[] | {id, status: .status.value}'
   curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:10100/v1/models
   ```

Verification: the unit is `active (running)`, the list shows every preset model, and the request without the key prints `401`.

## Switch the served model

Precondition: [Check the llama.cpp service](#check-the-llamacpp-service) passes.

1. For one launch, name another preset model:

   ```sh
   CLAUDE_LOCAL_MODEL=<model> claude-local
   codex -p local -m <model>
   ```

   The router unloads the current model before it loads the requested one.

2. To add a model, add an entry to `llamaModels` in [services.nix](../../../modules/hosts/songbird/services.nix), named as clients request it, with its Hugging Face repository in `hf-repo`.
   To make it the default, set `llamaModel` to that name and move `load-on-startup` to its entry, then switch.

3. Load a model ahead of the first request, which downloads it on first use:

   ```sh
   curl -s -H "Authorization: Bearer $(cat /run/secrets/llama-cpp/api-key)" -H 'Content-Type: application/json' -d '{"model": "<model>"}' http://127.0.0.1:10100/models/load
   ```

Verification: `/v1/models` shows the model with status `loaded`.

## Use a local model in Claude Code

Precondition: [Check the llama.cpp service](#check-the-llamacpp-service) passes.

1. Start Claude Code with every model slot on the default local model:

   ```sh
   claude-local
   ```

   It keeps the usual settings, hooks, and MCP servers, while plain `claude` stays on the hosted models.
   `claude-local --model` moves only the main slot, and the router reloads weights whenever two slots name different models.

2. For a smaller prompt, start it on a separate config directory, which drops the hosted login, hooks, plugins, and MCP servers:

   ```sh
   CLAUDE_CONFIG_DIR=~/.config/claude-local claude-local
   ```

Verification: `claude-local -p 'Reply with the word ready'` prints `ready`.

## Use a local model in Codex

Precondition: [Check the llama.cpp service](#check-the-llamacpp-service) passes.

1. Start Codex on the `local` profile that Home Manager generates:

   ```sh
   codex -p local
   ```

   The profile turns memories off, so the local model neither reads memories nor extracts them from past sessions.

Verification: `codex exec -p local --skip-git-repo-check 'Reply with the word ready' < /dev/null` prints `provider: llama-cpp` and `ready`.

## Open the web UI from the iPhone

Precondition: [Check the llama.cpp service](#check-the-llamacpp-service) passes, and the iPhone is on the LAN or the Mesh.

1. Open `http://<songbird-address>:10100` in Safari, using songbird's LAN address or its Mesh address (`ip -4 addr show CloudflareWARP`).

2. Paste the contents of `/run/secrets/llama-cpp/api-key` into the web UI settings.

Verification: a question about an attached photo gets an answer, and `curl -s -H "Authorization: Bearer <key>" 'http://<songbird-address>:10100/props?model=<model>' | jq .modalities.vision` prints `true` from a LAN host or a Mesh peer.

## Free the GPU

Precondition: none.

1. Unload the active model, or stop the service so no request loads one again:

   ```sh
   curl -s -H "Authorization: Bearer $(cat /run/secrets/llama-cpp/api-key)" -H 'Content-Type: application/json' -d '{"model": "<model>"}' http://127.0.0.1:10100/models/unload
   sudo systemctl stop llama-cpp
   ```

   `sudo systemctl start llama-cpp` brings the service back, and the next boot starts it too.

Verification: `nvidia-smi --query-compute-apps=process_name,used_memory --format=csv` lists no `llama-server`.
