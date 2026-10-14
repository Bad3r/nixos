# songbird Local AI Plan

Status: draft for review; decisions D1 to D8 and O1 to O9 are settled, and nothing here is implemented\
Host: `songbird` serves, `tpnix` and the iPhone are clients\
Scope: llama.cpp replaces Magnitude as the default local inference engine, LACT settings move into Nix, and the hardware follow-ups from the local AI evaluation are tracked.

## 1. Goal

songbird runs open-weight models on its RTX 5080 through one default engine, llama.cpp's `llama-server`.
It serves `claude-local` and `codex -p local` on songbird and tpnix, and the llama-server web UI to the iPhone, over the Cloudflare Mesh behind a sops-managed key.
Magnitude was an experiment and leaves the configuration.

## 2. Final State (Acceptance Definition)

1. `llama-server` is the only inference engine holding the RTX 5080, and the Magnitude module, user service, firewall port, secret wiring, and docs are gone.
2. `claude-local -p 'Reply with the word ready'` prints `ready` on songbird and on tpnix.
3. `codex exec -p local --skip-git-repo-check 'Reply with the word ready' < /dev/null` prints `ready` on songbird and on tpnix.
4. The iPhone opens the web UI over the Mesh, authenticates with the key, and gets an answer about an attached photo.
5. A request without the key gets HTTP 401 on every inference endpoint, from the Mesh and from loopback.
6. The CUDA llama-cpp substitutes from cache.nixos-cuda.org, so no CUDA code compiles on songbird or in CI.
7. `/etc/lact/config.yaml` is a Nix-managed symlink carrying the values the LACT GUI set.
8. The pages under `docs/hosts/songbird/` describe the llama.cpp setup, and `docs/usage/magnitude.md` is deleted.

## 3. Locked Decisions

Taken in the review of the local AI evaluation pages.

| #   | Question                                                | Decision                                                                                                           | Lands in                                                                                          |
| --- | ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| D1  | Where the overview page lives                           | Keep `docs/hosts/songbird/songbird-local-ai.md`; the style guide gains the `<host>-<topic>.md` topic overview type | This PR                                                                                           |
| D2  | DIMMs at 7400 MT/s                                      | Deliberate: XMP 8400 was unstable; the stable ceiling still needs testing (memtest86 is in the systemd-boot menu)  | Hardware page in this PR; tuning is manual                                                        |
| D3  | Windows Boot Manager on disk A's ESP                    | Give disk W its own ESP                                                                                            | Procedure in `songbird-runbook-windows.md`; the hardware page states the shared ESP until it runs |
| D4  | LACT versus "no OS-side fan software"                   | Reword the fan line; declare the GUI-set LACT values in Nix                                                        | Line in this PR; declaration in phase 1                                                           |
| D5  | Image questions from the iPhone                         | Add `--mmproj` with the model's projector                                                                          | Runbook in this PR                                                                                |
| D6  | Uses that need tools that are not installed             | Describe each use as what the RTX 5080 can run, without tool names; set the tooling up after review                | Overview in this PR                                                                               |
| D7  | Engine                                                  | llama.cpp replaces Magnitude as the single default engine                                                          | Phases 2 to 5                                                                                     |
| D8  | Links from the parent runbook and troubleshooting pages | Follow-up docs PR                                                                                                  | Issue #557                                                                                        |

The engine decisions O1 to O9 are in section 6.

## 4. Target Design

### 4.1 Engine and unit

llama.cpp here is nixpkgs `llama-cpp` 0.6.0 (build 11429) at the pinned revision.

- llama-server runs in router mode (O3): started without `-m`, it reads one section per model from `--models-preset` and loads a model when a request names it.
- `--models-max 1` keeps one model in the 16 GB at a time, so a request for another model evicts the loaded one, as Magnitude's scheduler does.
- The router has no default model: a request without a known `model` gets HTTP 400, so every client names its model, and the web UI offers a model picker.
- Each preset section sets the model's `hf-repo`, an alias, `c`, `ngl`, `ctk` and `ctv` at `q8_0`, an optional draft model, and `sleep-idle-seconds` to free VRAM when idle.
  An unknown key in the preset is fatal at startup.
- The unit is the nixpkgs `services.llama-cpp` module (O1): a system service under `DynamicUser` with state and cache directories, `LLAMA_CACHE=/var/cache/llama-cpp`, and `PrivateDevices=false`, so `/dev/nvidia*` stays reachable.
  A system unit serves the Mesh without a login session, which Magnitude's user service never did.
- Fixes that are not specific to songbird land on the `nixpkgs-unstable` branch of the Bad3r/nixpkgs fork (clone at `/data/Projects/igit/fork-nixpkgs`), pushed directly and kept upstreamable:
  - `ExecReload` sends SIGHUP, which llama-server does not handle, and `Restart=on-failure` counts that exit as clean, so a reload leaves the service down; drop `ExecReload`.
  - `RestartSec=300` delays every recovery by five minutes; lower it.
  - `settings` values join into `ExecStart` unescaped, so a value with a space splits into two arguments; quote each value, which keeps systemd specifiers such as `%d` working.
  - CUDA under the module's `ProcSubset=pid` and `MemoryDenyWriteExecute` is unverified; if the first CUDA start fails, relax both for CUDA packages, as the nixpkgs ollama module runs with `ProcSubset=all`.
- songbird-specific settings stay in this repository: the preset, the port, the key credential, and the firewall rule.
  `openFirewall` stays off, because it opens the port on every interface.
- Router children listen on random loopback ports without a key, so any local process on songbird reaches a loaded model; that is accepted on the single-user host (O8).
- The key goes in as `--api-key-file`, never as `LLAMA_API_KEY`: children inherit the environment, and the router's own calls to them carry no key.
- llama-swap (`services.llama-swap` in nixpkgs) would add a second process and a YAML config for what the built-in router already does.

### 4.2 Package and binary cache

- The engine package is `pkgs.llama-cpp-cuda` (O2): with `allowUnfree` it evaluates to `/nix/store/vyg0m0w8va1ziy176jkqlz1nkjvz78z5-llama-cpp-0.6.0`, the default-capability CUDA build (CUDA 12.9, capabilities 7.5 to 12.1, including the RTX 5080's 12.0).
- That path is on cache.nixos-cuda.org (414 MB closure) and not on cache.nixos.org; a custom `cudaCapabilities` would change the hash and compile locally instead.
- cache.nixos-cuda.org joins the `caches` list in `modules/hosts/common/nix-substituters.nix` with the key `cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=`, published on the NixOS wiki CUDA page.
  `nix store verify --no-contents` with that key accepts the cache's signature on the path above and rejects an altered key.
- The same list generates CI's substituters through `modules/meta/ci-substituter-parity.nix`, so the update-flake job substitutes the CUDA build instead of compiling it.
- The cache declares `Priority: 50`, so Lix asks it after cache.nixos.org (40), and each host pays one more narinfo lookup for every path the earlier caches miss.
- The same cache serves CUDA builds of whisper-cpp, ollama, and torch for the tooling planned after the swap.

### 4.3 Network and key

- llama-server binds every interface and the firewall opens its port only on `CloudflareWARP`, the pattern `modules/apps/magnitude.nix` uses.
  Binding the Mesh address instead fails whenever the interface comes up after the unit or changes its address.
- The port is 10100 (O4), Magnitude's Mesh-only port, outside the `firewallLocalTcpPortRanges` dev range (8000 to 8999) that `modules/hosts/common/firewall.nix` also opens to the LAN.
  It is set explicitly, since llama-server warns that its default moves from 8080 to 9931.
- The key comes from sops: `secrets/llama-cpp.yaml`, key `llama_cpp_api_key`, rendered at `/run/secrets/llama-cpp/api-key` on songbird and tpnix; the catch-all `secrets/.*` rule in `.sops.yaml` covers the file.
- The secret is a new value, not a rename of `magnitude_api_key`, because `~/.magnitude/config.json` holds a plaintext copy of the old key.
- The service reads the key through `LoadCredential` with `settings.api-key-file = "%d/api-key"`, where `%d` is the credentials directory, so no world-readable path or argv carries it.
- `--api-key-file` reads one key per line, skips `#` lines, and trims no whitespace, so the sops value carries no trailing spaces.
- Clients send `Authorization: Bearer <key>`; `X-Api-Key` counts only when that header is absent.
- Without the key, only `/health`, `/v1/health`, `/`, and the web UI's assets answer; the admin routes that load and unload models need it like every inference endpoint.
- Never pass `--tools`, `--agent`, `--ui-mcp-proxy`, `--mcp-servers-config`, or `--mcp-servers-json` on the Mesh listener; they expose shell commands, MCP tools, or a URL proxy.

### 4.4 Clients

- The `client.*` options move from `programs.magnitude.extended` to `programs.llama-cpp.extended.client` (O9): `endpoint`, `model`, `contextWindow`, and `apiKeyFile`.
- `modules/agents/claude-code/home-manager.nix:131-133` and `modules/agents/codex/home-manager.nix:106-108` read those options through `lib.attrByPath` with a null fallback, so a missed rename removes `claude-local` and `codex -p local` without an evaluation error.
  The new module asserts that a host with a non-null endpoint gets both client wrappers, so the rename fails loudly instead.
- Claude Code: `ANTHROPIC_BASE_URL` becomes the bare server origin, since llama-server serves `/v1/messages` at the root, and the key stays in `ANTHROPIC_AUTH_TOKEN`, sent as `Authorization: Bearer`.
  On `/v1/messages`, a `tool_choice` naming one tool becomes `required`, only `thinking.type = "enabled"` maps, and Anthropic server tools arrive as functions with an empty schema.
- Codex 0.162.1 accepts only `wire_api = "responses"` and rejects `"chat"` with a hard error, so the provider needs llama-server's `/v1/responses`.
  The provider ID must avoid the reserved `openai`, `ollama`, `lmstudio`, `amazon-bedrock`, and `amazon-bedrock-runtime`; `base_url` ends in `/v1`, and auth stays the `cat` command on the key file.
  The profile keeps `features.memories = false`, so Codex never posts past cloud threads to the local server.
- `/v1/responses` translates each request into a chat completion: `previous_response_id`, `input_file`, and unknown input item types return 400, and tools other than `function` are dropped.
  The Codex runtime gate in section 7 exercises that path end to end.
- `contextWindow` follows the server's `--ctx-size`, which feeds `CLAUDE_CODE_MAX_CONTEXT_TOKENS` and Codex's `model_context_window`.
- Every Claude Code model slot keeps pointing at one model, since a second model in another slot forces a weight swap on every turn.
- The iPhone uses the built-in web UI with the key, which replaces the ad hoc `spwnd` procedure in `songbird-runbook-local-ai.md`.

### 4.5 Models and storage

- Each preset section names its model's Hugging Face repository and file in `hf-repo`, and the server downloads it into `LLAMA_CACHE` (`/var/cache/llama-cpp` on disk A) on first load (O7).
- `--mmproj-auto`, on by default, fetches a vision model's projector with it, so the web UI accepts images without a separate `mmproj` key.
- The default model's section sets `load-on-startup`, so its download and load run when the service starts instead of inside a client request.
- `/data` holds no models: its unlock prompt can time out and leave the volume closed at boot.
- Model files never enter the Nix store: multi-gigabyte fixed-output derivations would bloat the store, every closure, and the cache-root set.
- The trial candidates are on disk already (O5):
  - `~/.magnitude/models/hub`: Qwen3.5 9B UD-Q5_K_XL, Gemma 4 12B QAT UD-Q4_K_XL, and MiniCPM5 2B Q8_0, with their projectors and drafters (19 GB).
  - `~/.cache/llama-eval`: Gemma 4 26B-A4B UD-IQ4_XS, Qwen3.8 27B UD-Q3_K_XL, and Qwen3.6 35B-A3B UD-Q4_K_XL (49 GB); the last one needs experts in RAM through `--n-cpu-moe`.
- Seeding the cache from those files saves about 68 GB of downloads, provided llama.cpp's cache layout accepts the Hugging Face hub layout Magnitude used; that is unverified.

### 4.6 Speculative decoding

- llama.cpp drafts with DFlash blocks (`spec-type = draft-dflash`), DSpark, EAGLE3, MTP, a plain draft model (`draft-simple`), or n-gram lookup.
- The type is detected from a DFlash or DSpark draft file; a plain draft GGUF needs `spec-type = draft-simple` set explicitly.
- Magnitude decodes Qwen3.5 9B at about 195 tokens per second with its DFlash drafter, against 125 for llama.cpp without drafting.
- Drafters for the three Magnitude models are on disk: DFlash for Qwen3.5 9B (1.38 GB), MTP for Gemma 4 12B QAT (0.25 GB), and DSpark for MiniCPM5 2B (0.65 GB).
- Qwen3.5 9B is measured with and without its DFlash drafter first; a model gets its drafter only where the speedup is worth the VRAM (O6).
- `--draft`, `--draft-max`, and `--draft-min` fail at this version; the flags are `--spec-draft-n-max` and `--spec-draft-n-min`.

### 4.7 GPU tuning (LACT)

`services.lact.settings` takes over `/etc/lact/config.yaml`, which nixpkgs then installs as a store symlink and restarts `lactd` on change.
The GPU key carries songbird's PCI address, so the block lives in `modules/hosts/songbird/services.nix` beside `lact.enable`:

```nix
services.lact.settings = {
  version = 7;
  daemon = {
    log_level = "info";
    admin_group = "wheel";
    disable_clocks_cleanup = false;
  };
  apply_settings_timer = 5;
  gpus."10DE:2C02-1043:8A47-0000:02:00.0" = {
    fan_control_enabled = false;
    power_mizer_mode = "PreferMaximumPerformance";
    power_cap = 450.0;
    voltage_boost = 100;
  };
  current_profile = null;
  auto_switch_profiles = false;
};
```

The 450 W cap is the card's maximum, and the prefill peak of about 365 W in `docs/hosts/songbird/songbird-local-ai.md` already exceeds the 360 W default.
Once the file is a store symlink, a change made in the LACT GUI no longer persists, so the module is the only place to tune.

## 5. Implementation Phases

1. LACT: declare the settings above, switch, and check that `readlink /etc/lact/config.yaml` points into the store and `nvidia-smi -q -d POWER` still reports a 450 W limit.
2. Fork: fix the generic `services.llama-cpp` issues from section 4.1 on Bad3r/nixpkgs `nixpkgs-unstable`, validate with `--override-input nixpkgs` against songbird's toplevel, and push; this repository picks the fix up with its next `flake.lock` update.
3. Engine swap, in one PR so two engines never compete for the GPU:
   - Add cache.nixos-cuda.org to the `caches` list in `modules/hosts/common/nix-substituters.nix`.
   - Add the llama.cpp module (unit, preset, firewall, sops secret, `client.*` options, assertion) and its apps-enable toggles in `modules/hosts/common/apps-enable.nix` and `modules/hosts/songbird/apps-enable.nix`.
   - Repoint `modules/agents/claude-code/home-manager.nix`, `modules/agents/claude-code/_launcher.nix` (`magnitudeClient`, the `magnitude-local` placeholder token, the reload comment), and `modules/agents/codex/home-manager.nix` (provider ID, `base_url`, header notes).
   - Replace `modules/tpnix/magnitude.nix` with the new endpoint for tpnix.
   - Delete `modules/apps/magnitude.nix` and both `magnitude` apps-enable entries together, since a toggle without its module fails host evaluation.
   - Add `secrets/llama-cpp.yaml` in the secrets repository, push it to its main branch, and bump the gitlink.
   - Rewrite the Magnitude parts of `docs/hosts/songbird/songbird-runbook-local-ai.md`, `docs/hosts/songbird/songbird-troubleshooting-local-ai.md`, the Speeds section of `docs/hosts/songbird/songbird-local-ai.md`, and `docs/hosts/songbird/songbird-configuration.md`; delete `docs/usage/magnitude.md` and its rows in `docs/usage/README.md` and `docs/index.md`.
4. Trial: load each preset model, run the same tool-calling tasks through `claude-local` and `codex -p local`, and measure Qwen3.5 9B with and without its drafter; then set the default model, its context size, and the drafters (O5, O6).
5. Host cleanup, run by the owner after the trial: remove `~/.magnitude`, `~/.cache/llama-eval`, `/var/lib/magnitude-desktop`, and `~/.config/codex/local.config.toml` (activation regenerates the last one).
6. Optional: drop `packages/magnitude` and its README entry from the Bad3r/llm-agents.nix fork.

The switch that drops the Magnitude module stops `magnitude-server`, since switch-to-configuration stops removed user units that are active.

## 6. Engine Decisions

Taken in the second review round.

| #   | Question                                  | Decision                                                                                                                      |
| --- | ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| O1  | Unit                                      | nixpkgs `services.llama-cpp` system unit; fixes that are not host-specific go to the Bad3r/nixpkgs fork for later upstreaming |
| O2  | CUDA package source                       | Add cache.nixos-cuda.org and use `pkgs.llama-cpp-cuda`, the cached default-capability build                                   |
| O3  | Model switching                           | Router with `--models-max 1`                                                                                                  |
| O4  | Port                                      | Reuse 10100, Mesh-only                                                                                                        |
| O5  | Models and default                        | Preset sections for the models already on disk; a tool-calling trial picks the default                                        |
| O6  | Drafters                                  | Measure Qwen3.5 9B with its DFlash drafter first, then decide per model                                                       |
| O7  | Model downloads                           | Preset `hf-repo` keys; the server downloads a model on first load                                                             |
| O8  | Router children on loopback without a key | Accepted on the single-user host                                                                                              |
| O9  | Client option namespace                   | `programs.llama-cpp.extended.client`                                                                                          |

## 7. Validation Gates

1. Format: `nix run path:.#treefmt -- .`
2. Evaluation: `nix flake check path:. --accept-flake-config --no-build --offline`
3. Closures: `nix build "path:.#nixosConfigurations.songbird.config.system.build.toplevel"`, then the same for `tpnix`.
4. Cache coverage: `scripts/cache-coverage.sh --host songbird` reports the `llama-cpp-cuda` path as substituted, not built.
5. Runtime on songbird:
   - `systemctl status` on the new unit is `active`, and `nvidia-smi --query-compute-apps=process_name,used_memory --format=csv` lists only llama-server.
   - A request without the key returns 401 on `/v1/chat/completions`, `/v1/responses`, and `/v1/messages`; with the key it returns 200.
   - `/props?model=<alias>` with the key reports `.modalities.vision` as `true` for a model with a projector; plain `/props` describes the router, not a model.
6. Clients on songbird and tpnix: the `claude-local` and `codex exec -p local` checks from section 2.
7. iPhone: the web UI answers a question about an attached photo.

## 8. Rollback

Switch to or boot the previous generation; it brings back `magnitude-server` and the Magnitude client wiring.
Magnitude's state stays on disk until phase 5, so the old generation runs unchanged.
Phase 5 is the one irreversible step and waits until the new engine has run for a while.

## 9. Primary Sources

- llama.cpp v0.6.0 server, router, and API key handling: <https://github.com/ggml-org/llama.cpp/tree/v0.6.0/tools/server>
- llama.cpp v0.6.0 speculative decoding: <https://github.com/ggml-org/llama.cpp/blob/v0.6.0/docs/speculative.md>
- nixpkgs `services.llama-cpp` at the pinned revision: <https://github.com/Bad3r/nixpkgs/blob/8a84254de235e4dcb7e20b0ee25587d1eda793e9/nixos/modules/services/misc/llama-cpp.nix>
- nixpkgs `services.lact` at the pinned revision: <https://github.com/Bad3r/nixpkgs/blob/8a84254de235e4dcb7e20b0ee25587d1eda793e9/nixos/modules/services/hardware/lact.nix>
- Codex wire API at the 0.162.1 branch point: <https://github.com/openai/codex/blob/ac9b5b8380517ded445b09dd3196d8d9e2ba3c59/codex-rs/model-provider-info/src/lib.rs>
- cache.nixos-cuda.org substituter and key: <https://wiki.nixos.org/wiki/Cuda>
