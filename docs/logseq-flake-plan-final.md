# Logseq Git Release Flake — Final Implementation Plan

_Last updated: 2025-10-05 (UTC)_

This document is the authoritative plan for building the `nix-logseq-git-flake` project. Follow each step exactly. The earlier exploratory draft remains at `docs/logseq-flake-plan.md` for reference only.

---

## Phase 0 · Repository Bootstrap (complete before writing other code)

1. **Create the local/GitHub repository.**
   - Ensure `~/git` exists; work inside it.
   - Run:
     1. `cd ~/git`
     2. `mkdir nix-logseq-git-flake && cd nix-logseq-git-flake`
     3. `git init -b main`
     4. `gh repo create nix-logseq-git-flake --public --source=. --remote=origin`
2. **Create initial file layout.** Add empty placeholders for upcoming content:
   - `flake.nix`
   - `data/logseq-nightly.json`
   - `.github/workflows/nightly.yml`
   - `.github/workflows/validate.yml`
   - `.gitignore` (use standard Nix ignores: `/result`, `/.direnv`, `/flake.lock.backup`)
   - Commit as `chore: scaffold repository layout` and push to `origin/main`.
3. **Configure Actions permissions.** In GitHub repo settings:
   - Enable Actions.
   - Grant workflows “Read and write permissions” so they can publish releases and push manifest updates.
   - No extra secrets are required; built-in `GITHUB_TOKEN` suffices.

---

## Phase 1 · Release Artifact & Manifest Specification

1. **Nightly schedule.** GitHub Actions workflow runs daily at 00:00 UTC (`cron: "0 0 * * *"`).
2. **Release tag & asset naming.**
   - Release tag/name: `nightly-${YYYYMMDD}` (UTC date).
   - Asset filename: `logseq-linux-x64-${logseqRev}.tar.gz` where `logseqRev` is the short commit hash of the upstream Logseq repo used for the build.
3. **Manifest location & schema.**
   - File path: `data/logseq-nightly.json` (committed to repo).
   - JSON object exactly:
     ```json
     {
       "tag": "nightly-20251005",
       "publishedAt": "2025-10-05T00:18:12Z",
       "assetUrl": "https://github.com/<owner>/nix-logseq-git-flake/releases/download/nightly-20251005/logseq-linux-x64-abcdef1.tar.gz",
       "assetSha256": "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
       "logseqRev": "abcdef1234567890",
       "logseqVersion": "nightly-20251005"
     }
     ```
   - `assetSha256` is the Nix base32 hash (use `nix hash file --type sha256 --to nix-base32`).
   - All timestamps are ISO8601 UTC with `Z` suffix.
4. **Host update model.** End-users receive new releases when they update their Nix configuration to the latest commit of this flake. The systemd timer introduced later does **not** run `nix flake update`; it only realises the already-pinned package.
5. **Release retention.** GitHub keeps nightly releases per its defaults; no automated deletion is performed. Local builds only materialise the latest store path.

---

## Phase 2 · Flake Structure & Common Assets

1. **Initial flake setup.** Run `nix flake init --template github:nix-community/templates#minimal` inside `~/git/nix-logseq-git-flake`, then edit to:
   - Declare inputs `nixpkgs` and `flake-utils` (pin `nixpkgs` to the channel used by your systems).
   - Use `flake-utils.lib.eachDefaultSystem` to expose system-specific outputs.
2. **Outputs (per system).**
   - `packages.logseq` — the packaged Electron app.
   - `apps.logseq` — convenience launcher mapping to the package executable.
   - `nixosModules.logseq` — NixOS module providing systemd timer/service and package wiring.
   - `checks.logseq` — minimal smoke test ensuring the package builds.
3. **Library helpers.** Add `lib/loadManifest.nix` that reads and validates `data/logseq-nightly.json`, ensuring all keys exist and the hash matches Nix format. Validation errors must be explicit (e.g., `throw "manifest missing assetUrl"`).
4. **Runtime dependency list.** Extract the runtime libraries from current `modules/apps/logseq.nix` (`alsa-lib`, `gtk3`, Xorg libs, etc.) and commit them in `lib/runtime-libs.nix` as a plain list for reuse.

---

## Phase 3 · Package Implementation (`packages.logseq`)

1. **Fetch release artifact.** Use `pkgs.fetchzip` with URL/hash from the manifest helper to retrieve the nightly tarball.
2. **Install layout.**
   - Unpack to `${placeholder}/Logseq-linux-x64`.
   - Install whole directory into `$out/share/logseq`.
   - Install icon from `static/resources/app/icon.png` into `$out/share/icons/hicolor/512x512/apps/logseq.png`.
3. **FHS wrapper.** Build an FHS environment via `pkgs.buildFHSEnv` with runtime libs imported from `lib/runtime-libs.nix`. Create wrapper script `$out/bin/logseq` invoking the upstream binary within the FHS env.
4. **Desktop entry.** Generate `/share/applications/logseq.desktop` with `Exec=logseq %U`, `Name=Logseq`, `Icon=logseq`, `Categories=Office;Productivity;`, and `StartupWMClass=Logseq`.
5. **Metadata.** Set `meta.version = manifest.logseqVersion`, `meta.sourceProvenance = [ manifest.logseqRev ]`, `meta.platforms = platforms.linux`.
6. **Smoke check.** Define `checks.logseq = pkgs.runCommand "logseq-smoke" { } ''nix run ${self}.#logseq -- --version >/dev/null''` (or equivalent) to ensure wrapper starts.

---

## Phase 4 · NixOS Module (`nixosModules.logseq`)

1. **Module file** `modules/logseq-module.nix` exports options:
   - `services.logseq.enable` (bool, default `false`).
   - `services.logseq.package` (package, default flake package).
   - `services.logseq.timerOnCalendar` (string, default `"02:00"`).
   - `services.logseq.logLevel` (enum `"info" | "warn" | "debug"`, default `"info"`).
   - `services.logseq.nixBinary` (path, default `${pkgs.nix}`) in case users pin custom `nix`.
   - `services.logseq.description` (string, default `"Nightly Logseq package realisation"`).
2. **Systemd service/unit implementation.**
   - Service `logseq-sync.service` (Type=oneshot) with `ExecStart=${pkgs.bash}/bin/bash -lc 'set -euo pipefail; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ); out=$(${cfg.nixBinary}/bin/nix build ${flakeRef}#logseq --print-out-paths); printf "{\"timestamp\":\"%s\",\"level\":\"info\",\"message\":\"logseq built\",\"storePath\":\"%s\"}\n" "$ts" "$out"'`.
   - On failure, trap to emit JSON error message with stderr captured to `/var/log` via journal (systemd handles Logging).
   - Timer `logseq-sync.timer` with `OnCalendar=${cfg.timerOnCalendar}` and `Persistent=true`.
   - `WantedBy=timers.target`.
3. **Environment.** Set `Environment="NIX_CONFIG=accept-flake-config = true"` and `WorkingDirectory=/etc/nixos` (assumes flake is checked out there; adjustable via option `services.logseq.buildDirectory` defaulting to `/etc/nixos`). Provide option allowing override.
4. **Package exposure.** When enabled, module ensures `cfg.package` is included in `environment.systemPackages` and the desktop entry/icon reach the system.
5. **Documentation.** Add module docstring describing required host behaviour: hosts must update flake input manually; timer simply realises attr.

---

## Phase 5 · GitHub Actions Workflows

1. **`nightly.yml`.**
   - Triggers: `schedule` (00:00 UTC) and manual `workflow_dispatch`.
   - Job `build-release` steps:
     1. Checkout repo.
     2. Install Nix (use `cachix/install-nix-action@v22` or current).
     3. Clone upstream Logseq (`git clone --depth 1 https://github.com/logseq/logseq.git`).
     4. Build release using the existing script path `./scripts/build.sh` (ensure command matches current local process; if `sss-update-logseq` uses `nix develop` + `sss-update-logseq -f`, replicate the necessary yarn/clojure steps directly—documented as `TODO` replaced with actual command in implementation).
     5. Archive `static/out/Logseq-linux-x64` into `logseq-linux-x64-${rev}.tar.gz`.
     6. Compute SHA256 `nix hash file --type sha256 --to nix-base32 logseq-linux-x64-${rev}.tar.gz`.
     7. Create or update release `nightly-${date}` using `gh release create --target main --notes "Automated nightly"` with `--clobber` to overwrite existing.
     8. Save metadata JSON (matching manifest schema) to `artifact-manifest.json`.
   - Job `update-manifest` (needs `build-release`):
     1. Download `artifact-manifest.json`.
     2. Overwrite `data/logseq-nightly.json` with this file.
     3. Run `nix fmt` (later configured in flake).
     4. Run `nix flake check` to ensure package builds with new manifest.
     5. Commit `chore: bump nightly manifest` and push.
   - Job `validate` (needs `update-manifest`):
     1. Run `nix build .#logseq` to confirm package realises.
     2. Run `nix run .#logseq -- --version` to ensure wrapper executes headless.
2. **`validate.yml`.**
   - Trigger: `push`, `pull_request`.
   - Steps:
     1. `nix flake check`.
     2. `nix build .#logseq`.
     3. `nix run .#logseq -- --version`.

---

## Phase 6 · Integration into `/home/vx/nixos`

1. **Add flake input.** In `/home/vx/nixos/flake.nix` inputs, add:
   ```nix
   nix-logseq-git-flake.url = "github:<your-gh-username>/nix-logseq-git-flake";
   ```
2. **Replace legacy module/package usage.**
   - Remove `modules/apps/logseq.nix` references from the productivity role.
   - Import module from flake: `imports = [ inputs.nix-logseq-git-flake.nixosModules.logseq ];`.
   - Configure options (example):
     ```nix
     services.logseq = {
       enable = true;
       timerOnCalendar = "02:00";
       buildDirectory = "/etc/nixos";
     };
     ```
   - Remove ghq-related dependencies specific to Logseq.
3. **Ensure package exposure.** Add `environment.systemPackages = [ inputs.nix-logseq-git-flake.packages.${system}.logseq ];` if not already included via module.

---

## Phase 7 · Validation Checklist

1. **Flake self-check.** In `~/git/nix-logseq-git-flake`, run:
   - `nix flake check --accept-flake-config`.
   - `nix build .#logseq`.
   - `nix run .#logseq -- --version`.
2. **Systemd dry run on staging host.**
   - Apply module (rebuild system).
   - `sudo systemctl start logseq-sync.service`.
   - Verify `journalctl -u logseq-sync.service -n20` shows JSON info log with store path.
   - Confirm timer scheduling via `systemctl list-timers logseq-sync.timer` (next run 02:00 UTC).
3. **Nightly workflow observation.** After first implementation push, ensure `nightly.yml` creates the release, updates manifest, and passes validation.
4. **Documentation update.** Modify `/home/vx/nixos/docs/logseq-local-workflow.md` to describe the release-download model, removing references to local source builds.

---

Plan is now fully aligned with clarified requirements: no custom sync helper beyond invoking `nix build`, no automatic flake updates, GitHub handles release retention, and the package behaves like a standard nixpkgs binary. Implementation can proceed.
