# Songbird local AI plan

Status: proposed implementation; runtime and cache gates must pass before the engine swap.\
Host: Songbird serves its local clients and the iPhone over the Mesh.\
Scope: replace Magnitude with llama.cpp, declare LACT settings, and retain the hardware follow-ups from the local AI evaluation.

## 1. Goal

Songbird runs open-weight models on its RTX 5080 through one default engine, llama.cpp's `llama-server`.
It serves `claude-local` and `codex -p local` locally, and its web UI serves the iPhone over the Cloudflare Mesh behind a sops-managed key.
The implementation removes Magnitude's module, service, firewall entry, secret wiring, and usage documentation together.
This documentation PR does not implement that replacement.

## 2. Acceptance criteria

1. Only the selected inference engine holds the GPU; the desktop remains usable.
2. `claude-local -p 'Reply with the word ready'` prints `ready` on Songbird.
3. `codex exec -p local --skip-git-repo-check 'Reply with the word ready' < /dev/null` prints `ready` on Songbird.
4. Both clients complete a multi-turn tool call and consume its result through the intended local provider.
5. The iPhone authenticates to the web UI and receives an answer about an attached photo.
6. Requests without the key get HTTP 401 on every inference endpoint of the authenticated listener, over the Mesh and loopback.
7. The selected CUDA package and its dependencies substitute from approved caches; missing coverage blocks rollout instead of silently compiling CUDA.
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

| ID  | Choice                                                                   |
| --- | ------------------------------------------------------------------------ |
| O1  | nixpkgs `services.llama-cpp`; generic fixes in the fork                  |
| O2  | Stock `pkgs.llama-cpp-cuda` from cache.nixos-cuda.org; coverage required |
| O3  | Router mode with `--models-max 1`                                        |
| O4  | Reuse port 10100, Mesh-only                                              |
| O5  | Trial existing model candidates before choosing the default              |
| O6  | Measure DFlash first; choose drafters per model                          |
| O7  | Hugging Face downloads into the service cache                            |
| O8  | Unauthenticated children accessible to trusted host processes            |
| O9  | `programs.llama-cpp.extended.client`                                     |

O8 does not authorize guest or container access to child listeners.
The isolation gate below verifies that boundary before deployment.

## 4. Target design

### Package and service

The lock selects Bad3r/nixpkgs `e6258921cf40e0372c1f70700cdb55a24e2bb858`: llama.cpp 0.7.0, build 11669, source commit `620d222`.
The recorded benchmark workload uses llama.cpp 0.6.0, build 11429; it is not a performance or cache result for the selected package.
Recheck source behavior and cache availability whenever the lock changes.

Use the nixpkgs system service with its dynamic user, state directory, `LLAMA_CACHE=/var/cache/llama-cpp`, and GPU device access.
The system service must serve without a desktop login and start when `/data` remains locked.
Generic fixes belong on a focused branch of Bad3r/nixpkgs, validated with `--override-input nixpkgs`, published, then consumed by an explicit lock update:

- Remove `ExecReload` sending SIGHUP: the pinned server handles SIGINT and SIGTERM, and a default SIGHUP termination can leave `Restart=on-failure` inactive.
- Reduce `RestartSec=300` and test recovery after a crash.
- Quote settings with systemd-aware argument escaping; test spaces, quotes, literal percent signs, and `%d` credential expansion.
- Test CUDA under `ProcSubset=pid` and `MemoryDenyWriteExecute=true`; relax only a setting demonstrated to block CUDA, with the failure recorded in the fix.

Keep host-specific preset, credential, port, and firewall configuration in this repository.
Do not add consumer-side service workarounds for defects that can be fixed in the fork.

### App registration and cache

The new app owns its `package` option and supplies that package to `services.llama-cpp.package`.
Follow [apps-module-registry.md](../guides/apps-module-registry.md): add a common baseline row and a flat Songbird `appEnable` override, and pass `host-songbird-apps-match-registry`.
Keep any CLI installation in the app module; a prerequisite requests another app at priority 1050 rather than installing its package elsewhere.
Remove Magnitude's baseline and host rows atomically with its module.

Use the stock CUDA capability set unless a measured requirement justifies changing it.
Evaluate the package after Songbird's overlays and allowlisted-unfree policy; package name and version alone do not establish the output path.
No store path, closure size, or cache-hit result from the 0.6.0 evaluation proves substitution for this derivation.

Add the approved `https://cache.nixos-cuda.org` URL and verified signing key to `extra-substituters` and `extra-trusted-public-keys` in `.github/actions/install-lix/substituters.conf`.
`modules/hosts/common/nix-substituters.nix` reads that file; the installer action applies it in CI, and `ci-substituter-parity` checks the integration.
Confirm the cache's current key from its primary documentation and verify the selected output's signature.

Run `scripts/cache-coverage.sh --host songbird --allow-dirty --verbose` after enabling the proposed service.
Inspect the selected CUDA output and its dependency graph: a zero exit code alone permits report classes such as `uncached-stock` and does not prove substitution.
A fresh-store build plan must contain no CUDA compilation; unpublished or inconclusive coverage blocks deployment pending a publication or build decision.
If CI publication is needed, review the app-package inventory in `modules/meta/cache-roots.nix` and [binary-cache-coverage-extension.md](../reference/binary-cache-coverage-extension.md).

### Router, models, and storage

Start without `-m`, with one model section per `--models-preset` entry and `--models-max 1`.
A request naming another model unloads the current one; a missing or unknown model gets HTTP 400.
Clients must name a preset model, and the web UI must offer the expected choices.

Each section sets `hf-repo` to the repository or `repo:quant`; use the separate `hf-file` key for an exact GGUF filename.
Set the alias, context, GPU layers, optional drafter, and idle timeout explicitly; set both `ctk` and `ctv` to `q8_0`.
Use one parallel slot per model before equating the client context window with the server context, and verify the accepted context at runtime.
Keep per-model choices in the preset: router CLI parameters override matching preset values.
An unknown preset key is fatal at startup.
Only the chosen default's section uses `load-on-startup`, keeping startup loads within the one-model cap; downloads should finish before the client trial.
The router also discovers cached models, so the preset is not a strict allowlist. Inspect `/v1/models` and control cache discovery before exposing additional models.
Automatic projector discovery is enabled unless disabled; verify the downloaded projector and image input with each vision model.

Models remain outside the Nix store in `/var/cache/llama-cpp` on disk A.
The service must not depend on unlocking `/data` or traversing the owner's home under `ProtectHome=true`.
Inventory existing files, model revisions, and ownership before seeding the dynamic user's cache or estimating download savings.
The evaluation candidates are Qwen3.5 9B, Gemma 4 12B QAT, MiniCPM5 2B, Gemma 4 26B-A4B, Qwen3.8 27B, and Qwen3.6 35B-A3B.
The recorded model files are under `~/.magnitude/models/hub` and `~/.cache/llama-eval`; their continued presence and cache-layout compatibility require verification.

Measure Qwen3.5 9B with and without its DFlash drafter before assigning drafters per model.
The pinned server supports DFlash, DSpark, EAGLE3, MTP, plain draft models, and n-gram lookup.
DFlash and DSpark draft files identify their type; a plain draft GGUF needs `spec-type = draft-simple`.
Use `--spec-draft-n-max` and `--spec-draft-n-min`; do not carry the obsolete `--draft`, `--draft-max`, or `--draft-min` flags.
Record model revision, context, cache types, GPU occupancy, and power settings for every new performance result.

### Network, credentials, and isolation

Bind the authenticated listener on all interfaces, with `services.llama-cpp.openFirewall` disabled.
Open port 10100 only on `CloudflareWARP`, using the existing Magnitude interface-scoped pattern.
Keep it outside the development range and verify the generated nftables rules; LAN and workload bridges must not gain access implicitly.
Binding a dynamic Mesh address directly makes service startup depend on interface readiness.

Create a fresh value in `secrets/llama-cpp.yaml`, key `llama_cpp_api_key`, and render `/run/secrets/llama-cpp/api-key` on Songbird.
Follow the host's secret-readiness contract, including `sopsRuntimeReady`, rather than enabling decryption merely because the encrypted file exists.
Use `LoadCredential` and `settings.api-key-file = "%d/api-key"`; keep key material out of argv and the Nix store.
Do not reuse the value copied into Magnitude's plaintext configuration.

Pass `--api-key-file`, not `LLAMA_API_KEY`: router children inherit the environment, while the router strips their API-key arguments and sends unauthenticated internal requests.
Key files carry one key per line, skip `#` lines, and do not trim whitespace.
Clients send `Authorization: Bearer`; `X-Api-Key` is considered only when that header is absent or empty.
Health and UI resources remain public; model administration and inference require authentication at the main listener.
Do not enable shell, agent, MCP, or URL-proxy features on the Mesh listener.

Router children bind random ports on `127.0.0.1` without a key; processes sharing the host network namespace can reach them.
Retain O8's accepted access for trusted host processes, while documenting that native agent execution may share that namespace.
Workload networking does not automatically expose host loopback: guest-to-host rules and declared gateway proxies control access.
Never register child ports as `workloads.host.services`, links, proxies, or runtime grant targets.
Any future workload access uses the authenticated endpoint through an explicit policy.
Verify native agent, `sbx`, declared guest, and container reachability rather than treating an owner account as proof of isolation.
If the measured boundary exceeds O8, stop and resolve it before deploying the router.

### Clients

Move `endpoint`, `model`, `contextWindow`, and `apiKeyFile` into `programs.llama-cpp.extended.client`.
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

## 5. Implementation sequence

1. Resolve source, cache, client compatibility, and isolation gates before scheduling the swap.
2. Declare verified LACT settings; check the managed file and effective power limit after switching.
3. Fix demonstrated generic service defects in the nixpkgs fork, validate against Songbird with `--override-input`, publish, and update the consuming lock deliberately.
4. Add the new app, preset, credentials, clients, firewall policy, and registry rows in one engine-swap PR; remove Magnitude's wiring and update its documentation atomically.
5. Trial each model, tool-calling workflow, and drafter; choose the default model and context from those results.
6. Verify rollback with retained Magnitude state and credentials before any separately approved cleanup. Archive recoverable state before removing it.
7. Remove the Magnitude package from the llm-agents fork only as a separate optional cleanup.

Explicitly stop Magnitude Desktop, `magnitude-server`, and ad hoc GPU processes before starting the system service.
After switching, check the removed user unit is stopped; a successful NixOS activation does not prove user-manager state.
Do not remove the generated Codex local profile during cleanup; activation owns its contents.

## 6. Validation gates

01. Targeted formatting and hooks for the edited files; a secrets-guard sweep precedes unfiltered `path:` evaluation.
02. Structural evaluation: `nix flake check path:. --accept-flake-config --no-build --offline`, including registry and client-presence checks.
03. Cache coverage, signature verification, and a fresh-store build plan for the actual selected package and dependencies.
04. Build Songbird only: `nix build "path:.#nixosConfigurations.songbird.config.system.build.toplevel"` after the cache gate.
05. Runtime: service active without desktop login or `/data`; GPU occupancy, crash recovery, configuration restart, and model switching all behave as intended.
06. Auth: exercise `/v1/chat/completions`, `/v1/responses`, `/v1/messages`, and administration from loopback and a Mesh peer, with missing, wrong, and valid keys.
07. Isolation: deny the main listener from LAN and ungranted workload bridges; confirm child listeners stay on loopback and cannot be reached from guests, containers, or `sbx` guests.
08. Clients: ready checks, multi-turn tools and results, interactive and daemon paths, context handling, memory exclusions, and iPhone image input.
09. Router vision: authenticated `/props?model=<alias>` reports vision for the loaded model; plain `/props` describes the router.
10. Rollback: stop the new system service, switch generation, start the old user service, and serve a verified request with retained state.

## 7. Recovery

Keep Magnitude's package, models, configuration, and old secret available until the previous generation has served a verified request.
Stop the new service before restarting the old engine; verify only one inference engine holds the GPU.
Cleanup of `~/.magnitude`, `~/.cache/llama-eval`, or `/var/lib/magnitude-desktop` requires separate approval and a recovery copy.
The engine trial does not authorize deletion or promise rollback after state removal.

## 8. Sources

- Pinned package: <https://github.com/Bad3r/nixpkgs/blob/e6258921cf40e0372c1f70700cdb55a24e2bb858/pkgs/by-name/ll/llama-cpp/package.nix>
- Server, router, adapters, and credentials: <https://github.com/ggml-org/llama.cpp/tree/v0.7.0/tools/server>
- Model arguments and preset keys: <https://github.com/ggml-org/llama.cpp/blob/v0.7.0/common/arg.cpp>
- Speculative decoding: <https://github.com/ggml-org/llama.cpp/blob/v0.7.0/docs/speculative.md>
- Pinned service: <https://github.com/Bad3r/nixpkgs/blob/e6258921cf40e0372c1f70700cdb55a24e2bb858/nixos/modules/services/misc/llama-cpp.nix>
- Pinned LACT module: <https://github.com/Bad3r/nixpkgs/blob/e6258921cf40e0372c1f70700cdb55a24e2bb858/nixos/modules/services/hardware/lact.nix>
- Cache key and CUDA packaging guidance: <https://wiki.nixos.org/wiki/CUDA>
