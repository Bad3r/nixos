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
   qwen -m <model>
   ```

   The router unloads the current model before it loads the requested one.

2. To add a model, add an entry to `llamaModels` in [services.nix](../../../modules/hosts/songbird/services.nix), named as clients request it, with its Hugging Face repository in `hf-repo`.
   To make it the default, set `llamaModel` to that name and move `load-on-startup` to its entry, then switch.

3. Load a model ahead of the first request, which downloads it on first use:

   ```sh
   curl -s -H "Authorization: Bearer $(cat /run/secrets/llama-cpp/api-key)" -H 'Content-Type: application/json' -d '{"model": "<model>"}' http://127.0.0.1:10100/models/load
   ```

Verification: `/v1/models` shows the model with status `loaded`.

## Use a local model in qwen-code

Precondition: [Check the llama.cpp service](#check-the-llamacpp-service) passes.

1. Start qwen-code in the project directory:

   ```sh
   qwen
   ```

   `qwen` reads the API key at launch and asks before every file edit and shell command.

2. To change a default, override its key in `~/.qwen/settings.json`; `/etc/qwen-code/system-defaults.json` holds the Nix-managed values.

Verification: `qwen -p 'Reply with the word ready'` prints `ready`.

## Open the web UI from the iPhone

Precondition: [Check the llama.cpp service](#check-the-llamacpp-service) passes, and the iPhone is on the LAN or the Mesh.

1. Open `http://<songbird-address>:10100` in Safari, using songbird's LAN address or its Mesh address (`ip -4 addr show CloudflareWARP`).

2. Paste the contents of `/run/secrets/llama-cpp/api-key` into the web UI settings.

Verification: a question about an attached photo gets an answer, and `curl -s -H "Authorization: Bearer <key>" 'http://<songbird-address>:10100/props?model=<model>' | jq .modalities.vision` prints `true` from a LAN host or a Mesh peer.

## Transcribe a recording

Precondition: a shell on songbird as the owner, and a recording.

1. The server decodes only WAV, MP3, and FLAC, so convert any other recording to WAV first:

   ```sh
   ffmpeg -i <input> -ac 1 -ar 16000 <recording>.wav
   ```

2. Send the file to the speech-to-text service and strip the language prefix from the transcript:

   ```sh
   curl -s -H "Authorization: Bearer $(cat /run/secrets/llama-cpp/api-key)" -F file=@<recording> -F language=en http://127.0.0.1:10102/v1/audio/transcriptions | jq -r '.text | sub("^language [^<]*<asr_text>"; "")'
   ```

   The `language` field is optional; the first request after an idle period waits while the model reloads.

3. Show the unit and its log when the request fails:

   ```sh
   systemctl status llama-cpp-transcribe
   journalctl -u llama-cpp-transcribe -b
   ```

Verification: the command prints the transcript without the `language` prefix, and the same request without the key prints `401`:

```sh
curl -s -o /dev/null -w '%{http_code}\n' -F file=@<recording> http://127.0.0.1:10102/v1/audio/transcriptions
```

## Open a live dictation session

Precondition: a shell on songbird as the owner.

1. Open a session on the dictation service and print its first event:

   ```sh
   nix run nixpkgs#websocat -- -1 -U -H="Authorization: Bearer $(cat /run/secrets/llama-cpp/api-key)" 'ws://127.0.0.1:10103/v1/realtime?intent=transcription'
   ```

2. Show the unit and its log when the session fails:

   ```sh
   systemctl status llama-cpp-dictate
   journalctl -u llama-cpp-dictate -b
   ```

Verification: the command prints a `session.created` event whose `session.audio.input.format.rate` is the sample rate a client sends.

## Free the GPU

Precondition: none.

1. Unload the active model, or stop the service so no request loads one again:

   ```sh
   curl -s -H "Authorization: Bearer $(cat /run/secrets/llama-cpp/api-key)" -H 'Content-Type: application/json' -d '{"model": "<model>"}' http://127.0.0.1:10100/models/unload
   sudo systemctl stop llama-cpp
   ```

   `sudo systemctl start llama-cpp` brings the service back, and the next boot starts it too.

Verification: `nvidia-smi --query-compute-apps=process_name,used_memory --format=csv` lists no `llama-server`.
