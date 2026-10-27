# Songbird local AI plan

Status: implementation steps 1 to 6 done; the runtime and isolation gates run against the deployed service.\
Host: Songbird serves its local clients, the LAN, and the iPhone over the Mesh.\
Scope: replace Magnitude with llama.cpp, declare LACT settings, and retain the hardware follow-ups from the local AI evaluation.

## 1. Goal

Songbird runs open-weight models on its RTX 5080 through one default engine, llama.cpp's `llama-server`.
It serves `claude-local` and `codex -p local` locally, and its web UI serves the LAN and the iPhone over the Cloudflare Mesh behind a sops-managed key.
The implementation removes Magnitude's module, service, firewall entry, secret wiring, and usage documentation together.

## 2. Acceptance criteria

1. Only the selected inference engine holds the GPU; the desktop remains usable.
2. `claude-local -p 'Reply with the word ready'` prints `ready` on Songbird.
3. `codex exec -p local --skip-git-repo-check 'Reply with the word ready' < /dev/null` prints `ready` on Songbird.
4. Both clients complete a multi-turn tool call and consume its result through the intended local provider.
5. The iPhone authenticates to the web UI and receives an answer about an attached photo.
6. Requests without the key get HTTP 401 on every inference endpoint of the authenticated listener, over the LAN, the Mesh, and loopback.
7. The CUDA llama.cpp package builds on Songbird for sm_120 only; its dependencies substitute from approved caches.
8. `/etc/lact/config.yaml` is Nix-managed and carries verified GPU settings.
9. The host documentation describes the deployed engine; `docs/usage/magnitude.md` and its index entries are removed with the module.

## 3. Design decisions

- D1: keep the local AI overview beside the host's topic runbook and troubleshooting splits.
- D2: retain the hardware correction to 7400 MT/s; finding the stable memory ceiling remains manual tuning.
- D3: give disk W its own ESP through the Windows runbook; keep the shared-ESP warning until the procedure runs.
- D4: describe the GPU's fan curve separately from BIOS-controlled case fans, and declare verified LACT settings.
- D5: retain image support through a vision projector.
- D6: describe hardware uses without implying that every speech, image, or document tool is configured.
- D7: use llama.cpp as the single default inference engine.
- D8: parent runbook and troubleshooting navigation remains the follow-up tracked in issue #557.

The engine choices remain:

| ID  | Choice                                                                                            |
| --- | ------------------------------------------------------------------------------------------------- |
| O1  | nixpkgs `services.llama-cpp`; generic fixes in the fork                                           |
| O2  | Fork `pkgs.llama-cpp-cuda`, sm_120 only, built on Songbird; CUDA inputs from cache.nixos-cuda.org |
| O3  | Router mode with `--models-max 1`                                                                 |
| O4  | Reuse port 10100, LAN and Mesh                                                                    |
| O5  | Gemma 4 26B-A4B default, picked by the trial                                                      |
| O6  | Measure DFlash first; choose drafters per model                                                   |
| O7  | Hugging Face downloads into the service cache                                                     |
| O8  | Unauthenticated children accessible to trusted host processes                                     |
| O9  | `programs.llama-cpp.extended.client`                                                              |

O8 does not authorize guest or container access to child listeners.
The isolation gate below verifies that boundary before deployment.
Owner decisions of 2026-10-26: key holders may download and delete router models through the model API, an accepted risk; "Trial outcome" below names the default model.

## 4. Target design

### Package and service

The lock selects the fork's `nixpkgs-unstable` head `ccf94403077a05ae063e66a4342fb0d5852290dc`, which adds the service fixes below and the CUDA-only system-message fold to upstream `5d62642594b0`.
It builds llama.cpp 0.7.0, build 11669, source commit `620d222`; the CPU package keeps its stock derivation.
The recorded benchmark workload uses llama.cpp 0.6.0, build 11429; it is not a performance or cache result for the selected package.
Recheck source behavior and cache availability whenever the lock changes.

Use the nixpkgs system service with its dynamic user, state directory, `LLAMA_CACHE=/var/cache/llama-cpp`, and GPU device access.
The system service must serve without a desktop login and start when `/data` remains locked.
The fork head carries the generic service fixes; the engine-swap PR consumes them through a lock update:

- No `ExecReload`: the pinned server handles only SIGINT and SIGTERM, and a SIGHUP exit left `Restart=on-failure` inactive.
- `RestartSec = 10`; gate 05 tests recovery after a crash.
- `utils.escapeSystemdExecArgs` escapes every setting, so spaces, quotes, `%`, and `$` reach the server literally.
- `apiKeyFile` loads the key through `LoadCredential` and appends `--api-key-file %d/api-key`; an assertion rejects `settings.api-key` and `settings.api-key-file` beside it.

Still open: test CUDA under `ProcSubset=pid` and `MemoryDenyWriteExecute=true`; relax only a setting demonstrated to block CUDA, with the failure recorded in a fork fix.

Keep host-specific preset, credential, port, and firewall configuration in this repository.
Do not add consumer-side service workarounds for defects that can be fixed in the fork.

### App registration and cache

The new app owns its `package` option and supplies that package to `services.llama-cpp.package`.
Follow [apps-module-registry.md](../guides/apps-module-registry.md): add a common baseline row and a flat Songbird `appEnable` override, and pass `host-songbird-apps-match-registry`.
Keep any CLI installation in the app module; a prerequisite requests another app at priority 1050 rather than installing its package elsewhere.
Remove Magnitude's baseline and host rows atomically with its module.

The app's `package` defaults to `pkgs.llama-cpp-cuda` with the stock CUDA capability set; the service's own default is the CPU build.
Songbird sets it to the same package built for capability 12.0 alone, through a `cudaPackages` override on llama-cpp, so the CUDA redistributables keep their cached derivations.
The fork applies its system-message fold to llama-cpp-cuda only, which already keeps cache.nixos-cuda.org from serving it; dropping the nine other architectures cuts the local compile to about 4 minutes.
CPU llama-cpp, whisper-cpp, and ffmpeg-full keep their stock derivations and come from cache.nixos.org.
Songbird's pkgs refuse the CUDA build until the app module allowlists `cccl`, `cuda_cudart`, `cuda_nvcc`, `libnvvm`, `cuda_crt`, `libcublas`, and `cuda_nvrtc` in `nixpkgs.allowedUnfreePackages`.
Through Songbird's overlays and the sm_120 override, the output is `/nix/store/6b18cz21ycbz9slyfzmm97wvz9nj8cps-llama-cpp-cuda-0.7.0`.
Gate 03 checked the stock output of its lock, `/nix/store/6avc3v3yrns0imfy308qy2zs4bgqd3gh-llama-cpp-0.7.0`.

Gate 03 passed on 2026-10-26 for the main lock, before the fold patch and the sm_120 override made the package a local build.
cache.nixos-cuda.org then served the stock output and its 18-path, 1.2 GiB runtime closure, every path verified against key `cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=`, and a fresh-store plan with cache.nixos.org built nothing.
It still serves the CUDA build inputs and runtime libraries of Songbird's local build.
Without the cache, the plan compiled 26 derivations, including CUDA llama.cpp and nodejs.

`vx` is not a trusted user, so the host daemon ignores a client-side `extra-substituters`.
Main commit `a4a73a25` adds the URL and key to `extra-substituters` and `extra-trusted-public-keys` in `.github/actions/install-lix/substituters.conf` and `build.sh`; Songbird runs it before the engine swap is switched.
`modules/hosts/common/nix-substituters.nix` reads that file; the installer action applies it in CI, and `ci-substituter-parity` checks the integration.
After a lock change, rerun `scripts/cache-coverage.sh --host songbird --allow-dirty --verbose` and inspect the CUDA output's graph: a zero exit code alone permits `uncached-stock`.

### Router, models, and storage

Start without `-m`, with one model section per `--models-preset` entry and `--models-max 1`.
A request naming another model unloads the current one; a missing or unknown model gets HTTP 400.
Clients must name a preset model, and the web UI must offer the expected choices.

Each section sets `hf-repo` to the repository or `repo:quant`; use the separate `hf-file` key for an exact GGUF filename.
The section name is the model ID clients send, and the router sets it as the child's alias, so sections carry no `alias` key.
Set the context, GPU layers, optional drafter, and idle timeout explicitly; set both `ctk` and `ctv` to `q8_0`.
Use one parallel slot per model before equating the client context window with the server context, and verify the accepted context at runtime.
Keep per-model choices in the preset: router CLI parameters override matching preset values.
An unknown preset key is fatal at startup.
Only the default's section, Gemma 4 26B-A4B, uses `load-on-startup`, keeping startup loads within the one-model cap; downloads should finish before the client trial.
The router always lists and loads every model in its cache; no flag disables that, and `dedup-cache-models` only hides a cache entry a preset section resolves to.
Authenticated clients can download any Hugging Face repository with `POST /models` and delete cache-sourced models with `DELETE /models`; no flag disables either.
Automatic projector discovery is enabled unless disabled; verify the downloaded projector and image input with each vision model.

Models remain outside the Nix store in `/var/cache/llama-cpp` on disk A.
The service must not depend on unlocking `/data` or traversing the owner's home under `ProtectHome=true`.
Inventory existing files, model revisions, and ownership before seeding the dynamic user's cache or estimating download savings.
The evaluation candidates are Qwen3.5 9B, Gemma 4 12B QAT, MiniCPM5 2B, Gemma 4 26B-A4B, Qwen3.8 27B, and Qwen3.6 35B-A3B.
The recorded model files are under `~/.magnitude/models/hub` and `~/.cache/llama-eval`; their continued presence and cache-layout compatibility require verification.

Measure Qwen3.5 9B with and without its DFlash drafter before assigning drafters per model.
The pinned server supports DFlash, DSpark, EAGLE3, MTP, plain draft models, and n-gram lookup.
DFlash and DSpark draft files and MTP heads are detected automatically.
A local EAGLE3 draft needs `spec-type = draft-eagle3`, and a plain draft GGUF needs `spec-type = draft-simple`.
Use `--spec-draft-n-max` and `--spec-draft-n-min`; do not carry the obsolete `--draft`, `--draft-max`, or `--draft-min` flags.
Record model revision, context, cache types, GPU occupancy, and power settings for every new performance result.

### Network, credentials, and isolation

Bind the authenticated listener on all interfaces, with `services.llama-cpp.openFirewall` disabled.
Add port 10100 to `firewallLocalTcpPortRanges` in `modules/hosts/songbird/policy.nix`, replacing Magnitude's `CloudflareWARP`-only rule.
`modules/hosts/common/firewall.nix` opens those ranges from 10.0.0.0/8, 192.168.0.0/16, and on `CloudflareWARP`, so the LAN and the Mesh reach the listener on equal terms.
Workload bridges stay closed: the `inet workload` input chain drops new `vn-*` traffic before `nixos-fw`.
Podman's default subnet pools in `modules/apps/podman/nixos.nix` sit outside both LAN ranges; verify the generated nftables rules.
Binding one interface's address would shut out the other network and tie service startup to that interface's readiness.

Create a fresh value in `secrets/llama-cpp.yaml`, key `llama_cpp_api_key`, and render `/run/secrets/llama-cpp/api-key` on Songbird.
Follow the host's secret-readiness contract, including `sopsRuntimeReady`, rather than enabling decryption merely because the encrypted file exists.
Set `services.llama-cpp.apiKeyFile` to that path; the module loads it as a systemd credential, keeping key material out of argv and the Nix store.
Do not reuse the value copied into Magnitude's plaintext configuration.

Never set `LLAMA_API_KEY` instead of `apiKeyFile`: router children inherit the environment, while the router strips their API-key arguments and sends unauthenticated internal requests.
Key files carry one key per line, skip `#` lines, and do not trim whitespace.
Clients send `Authorization: Bearer`; `X-Api-Key` is considered only when that header is absent or empty.
Health and UI resources remain public; model administration and inference require authentication at the main listener.
Do not enable shell, agent, MCP, or URL-proxy features on the network listener.

Router children bind random ports on `127.0.0.1` without a key; processes sharing the host network namespace can reach them.
Retain O8's accepted access for trusted host processes, while documenting that native agent execution may share that namespace.
Workload networking does not automatically expose host loopback: guest-to-host rules and declared gateway proxies control access.
Never register child ports as `workloads.host.services`, links, proxies, or runtime grant targets.
Any future workload access uses the authenticated endpoint through an explicit policy.
Verify native agent, `sbx`, declared guest, and container reachability rather than treating an owner account as proof of isolation.
If the measured boundary exceeds O8, stop and resolve it before deploying the router.

### Clients

Move `endpoint`, `model`, `contextWindows`, and `apiKeyFile` into `programs.llama-cpp.extended.client`.
Update `modules/agents/claude-code/home.nix`, its `_launcher.nix`, and `modules/agents/codex/home.nix` together.
Both consumers use a null endpoint fallback; assert or test that a non-null endpoint produces both local clients so a missed rename cannot silently remove them.
Preserve launcher behavior, configuration layering, and daemon startup while changing the provider wiring.

Claude's base URL becomes the bare server origin for `/v1/messages`; retain the bearer token, explicit context size, and every model-slot override.
The adapter maps a named `tool_choice` to `required`, only maps `thinking.type = "enabled"`, and represents tools as functions, using empty schemas when `input_schema` is absent.
Exercise actual client tool calls rather than treating HTTP 200 as full compatibility.

Preserve Codex's `wire_api = "responses"`, local `model` and `review_model`, and key-file `cat` authentication with a separate path argument.
Use a non-reserved provider ID and a base URL ending in `/v1`.
Preserve both `features.memories = false` and `memories.generate_memories = false`; verify the pinned client's behavior without claiming these exclude every possible source of context.
The Responses adapter rejects nonempty `previous_response_id`, `input_file`, and unknown item types, and drops non-function tools.
Test fresh one-shot execution and interactive/profile startup, including shared-daemon behavior and persistent configuration overrides.
Exercise a harmless request that triggers automatic approval review and verify that subsystem's provider and context handling separately.
Setting `review_model` does not by itself prove where automatic approval-review traffic goes; resolve any unintended hosted routing before accepting private local use.
Keep client context limits consistent with the selected model's server context.
The iPhone uses the authenticated built-in web UI, replacing the ad hoc runbook server after deployment.

### LACT

Keep enablement in `modules/hosts/songbird/apps-enable.nix`; host-specific settings belong in `modules/hosts/songbird/services.nix`.
Capture the live configuration, supported schema, GPU identifier, and power limits before applying this candidate configuration:

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

Validate the current card's supported limits rather than inferring them from the benchmark power draw.
The store-managed configuration must preserve the intended settings after restart; GUI persistence must be checked before relying on GUI edits.

### Trial outcome

The preset in `modules/hosts/songbird/services.nix` keeps six sections; raw results stay outside the repository.

- `gemma-4-26b-a4b` stays the default: it is the only preset that passes every client, tool, and vision check.
- `lfm2.5-24b-a2b` is the fast text-only preset, decoding 273 and 230 tokens per second at 1.9k and 31k-token prompts; its weaker tool picks make it a bulk-work model.
- `mimo-v2.6-9b` is the light vision and agent preset, but it ignores `tool_choice = required` in 5 of 9 requests, so paperless does not use it.
- `qwen3.8-27b-gsq-mtp`: its chat template rejects the non-leading system messages that Claude Code and Codex send.
  Claude Code passed through a folding proxy; the fork's in-server fold is meant to cover both clients and awaits the post-switch check.
- `minicpm5-2b` and `minicpm5-2b-dspark` stay as the small preset and its DSpark-drafted variant.
- Dropped: `muse-glimmer-30b`, the unsloth `qwen3.8-27b`, `qwen3.8-27b-gsq` without MTP, and `lfm2.5-24b-a2b-dspark`.

Upstream llama.cpp has no fold: https://github.com/ggml-org/llama.cpp/issues/27367 closed as stale, and https://github.com/ggml-org/llama.cpp/pull/27131 only reorders system messages.

## 5. Implementation sequence

1. Done 2026-10-26: source, cache, and client compatibility gates; CUDA hardening and isolation need the running service (gates 05 and 07).
2. Done: verified LACT settings landed on main as `75eafe79`.
3. Done: the service fixes are on the fork's `nixpkgs-unstable` at `a4b6aef616e9`.
4. Done: the cache landed on main as `a4a73a25`, and Songbird switched to it.
5. Done in this change, on a lock that pins the fork head: add the new app, preset, credentials, clients, firewall policy, and registry rows in one engine-swap PR; remove Magnitude's wiring and update its documentation atomically.
6. Done 2026-10-27: trialled each model, tool-calling workflow, and drafter; the outcome is under "Trial outcome" in section 4.
7. Verify rollback with retained Magnitude state and credentials before any separately approved cleanup. Archive recoverable state before removing it.
8. Remove the Magnitude package from the llm-agents fork only as a separate optional cleanup.

Explicitly stop Magnitude Desktop, `magnitude-server`, and ad hoc GPU processes before starting the system service.
After switching, check the removed user unit is stopped; a successful NixOS activation does not prove user-manager state.
Do not remove the generated Codex local profile during cleanup; activation owns its contents.

## 6. Validation gates

01. Targeted formatting and hooks for the edited files; a secrets-guard sweep precedes unfiltered `path:` evaluation.
02. Structural evaluation: `nix flake check path:. --accept-flake-config --no-build --offline`, including registry and client-presence checks.
03. Cache coverage, signature verification, and a fresh-store build plan for the actual selected package and dependencies.
04. Build Songbird only: `nix build "path:.#nixosConfigurations.songbird.config.system.build.toplevel"` after the cache gate.
05. Runtime: service active without desktop login or `/data`; GPU occupancy, crash recovery, configuration restart, and model switching all behave as intended.
06. Auth: exercise `/v1/chat/completions`, `/v1/responses`, `/v1/messages`, and administration from loopback, a LAN peer, and a Mesh peer, with missing, wrong, and valid keys.
07. Isolation: a LAN request without the key gets 401; deny the main listener from ungranted workload bridges; confirm child listeners stay on loopback and cannot be reached from guests, containers, or `sbx` guests.
08. Clients: ready checks, multi-turn tools and results, interactive and daemon paths, context handling, memory exclusions, and iPhone image input.
09. Router vision: authenticated `/props?model=<alias>` reports vision for the loaded model; plain `/props` describes the router.
10. Rollback: stop the new system service, switch generation, start the old user service, and serve a verified request with retained state.

## 7. Recovery

Keep Magnitude's package, models, configuration, and old secret available until the previous generation has served a verified request.
Stop the new service before restarting the old engine; verify only one inference engine holds the GPU.
Cleanup of `~/.magnitude`, `~/.cache/llama-eval`, or `/var/lib/magnitude-desktop` requires separate approval and a recovery copy.
The engine trial does not authorize deletion or promise rollback after state removal.

## 8. Sources

- Fork head package: <https://github.com/Bad3r/nixpkgs/blob/ccf94403077a05ae063e66a4342fb0d5852290dc/pkgs/by-name/ll/llama-cpp-cuda/package.nix>
- Server, router, adapters, and credentials: <https://github.com/ggml-org/llama.cpp/tree/v0.7.0/tools/server>
- Model arguments and preset keys: <https://github.com/ggml-org/llama.cpp/blob/v0.7.0/common/arg.cpp>
- Speculative decoding: <https://github.com/ggml-org/llama.cpp/blob/v0.7.0/docs/speculative.md>
- Fork head service: <https://github.com/Bad3r/nixpkgs/blob/a4b6aef616e977490ff24c44e37d412ac6b7b990/nixos/modules/services/misc/llama-cpp.nix>
- Fork head LACT module: <https://github.com/Bad3r/nixpkgs/blob/a4b6aef616e977490ff24c44e37d412ac6b7b990/nixos/modules/services/hardware/lact.nix>
- Cache key and CUDA packaging guidance: <https://wiki.nixos.org/wiki/CUDA>
