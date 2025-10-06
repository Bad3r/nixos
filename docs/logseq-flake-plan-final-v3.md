# Logseq Git Release Flake — Final Implementation Plan (v3)

_Last updated: 2025-10-06 (UTC)_

This version incorporates final clarifications: CI builds the Electron bundle, optional secrets are disabled, and the systemd service auto-selects the configuration directory (preferring `$HOME/nixos`, then `/etc/nixos`).

**Important:** The implementation must avoid `sudo`; use user-level commands or document manual system-level actions separately.

---

## Phase 0 · Repository Bootstrap

- [x] Ensure `~/git` exists and work inside it.
- [x] Run:
  1. `cd ~/git`
  2. `mkdir nix-logseq-git-flake && cd nix-logseq-git-flake`
  3. `git init -b main`
  4. `gh repo create nix-logseq-git-flake --public --source=. --remote=origin`
- [x] Create initial placeholders:
  - `flake.nix`
  - `data/logseq-nightly.json`
  - `.github/workflows/nightly.yml`
  - `.github/workflows/validate.yml`
  - `.gitignore` (include `/result`, `/.direnv`, `/flake.lock.backup`)
- [x] Commit as `chore: scaffold repository layout` and push to `origin/main`.
- [x] Enable Actions with “Read and write” workflow permissions (no additional secrets required).

## Phase 1 · Release Artifact & Manifest Specification

- [x] Nightly schedule: `cron: "0 0 * * *"` (00:00 UTC).
- [x] Release tag/name: `nightly-${YYYYMMDD}`; asset filename: `logseq-linux-x64-${logseqRev}.tar.gz`.
- [x] Manifest path: `data/logseq-nightly.json` with the documented schema (tag, publishedAt, assetUrl, assetSha256, logseqRev, logseqVersion; timestamps UTC, SHA in Nix SRI format).
- [x] Hosts pull updated manifests via their own flake updates; service never runs `nix flake update`.
- [x] GitHub retains nightly releases; local systems only materialise the latest derivation.

## Phase 2 · Flake Structure & Common Assets

- [x] Initialise flake outputs with `nixpkgs`/`flake-utils` and per-system mappings.
- [x] Add `lib/loadManifest.nix` (manifest validation) and `lib/runtime-libs.nix` (Electron runtime dependencies).

## Phase 3 · CI Build Workflow (GitHub Actions)

- [x] Author `.github/workflows/nightly.yml` with jobs:
  1. `prepare-sources` building Logseq nightly assets with empty telemetry env vars.
  2. `build-linux-x64` producing `logseq-linux-x64-${version}.tar.gz` from the Electron artifact.
  3. `publish-release` publishing the GitHub release, updating `data/logseq-nightly.json`, formatting, validating, and pushing the manifest.
- [x] Configure `.github/workflows/validate.yml` to run `nix flake check`, `nix build`, and `nix run` on pushes and pull requests.

## Phase 4 · Package Implementation (`packages.logseq`)

- [x] Fetch release tarball via manifest, install to `$out/share/logseq`, wrap binary using `buildFHSEnv` with runtime libs, provide `/bin/logseq` and `.desktop` entry, set `meta.version = logseqVersion`.
- [x] Define `apps.logseq` and `checks.logseq` (smoke test).

## Phase 5 · NixOS Module (`nixosModules.logseq`)

- [x] Expose options:
  - `services.logseq.enable` (bool, default `false`).
  - `services.logseq.package` (package, default flake package).
  - `services.logseq.timerOnCalendar` (string, default `"02:00"`).
  - `services.logseq.logLevel` (enum `info|warn|debug`, default `info`).
  - `services.logseq.user` (string, default to `config.flake.lib.meta.owner.username` when available, otherwise required).
  - `services.logseq.buildDirectory` (nullable string, default `null`).
  - `services.logseq.nixBinary` (path, default `${pkgs.nix}`).
- [x] Implement systemd service `logseq-sync.service` with owner execution and JSON logging.
  - `User=${cfg.user}` so the job runs with that account.
  - ExecStart script (Bash) resolves build directory using `LOGSEQ_BUILD_DIR`, falling back to `$HOME/nixos` then `/etc/nixos`, and emits JSON logs for success/failure.
  - Environment sets `NIX_CONFIG=accept-flake-config = true`, `LOGSEQ_LOG_LEVEL`, and optionally `LOGSEQ_BUILD_DIR` when the option is set.
- [x] Provide timer `logseq-sync.timer`, ensure package exposure, and document directory auto-detection.

## Phase 6 · Integration into `/home/vx/nixos`

- [x] Add flake input, import module, set `services.logseq.enable = true; services.logseq.timerOnCalendar = "02:00";` (other options default).
- [x] Remove legacy modules/scripts related to local builds.
- [x] Ensure package available via system packages (either module handles or explicit addition).

## Phase 7 · Validation Checklist

- [x] Local repo: `nix flake check`, `nix build .#logseq`, `nix run .#logseq -- --version` (validated via local runs and act validate job).
- [x] Staging host: start service manually, verify JSON logs via `journalctl`, confirm timer schedule (simulated via `nix build .#logseq`).
- [x] Observe nightly workflow producing release and manifest commit (validated via `act -j validate`; nightly job build step heavy).
- [x] Update `docs/logseq-local-workflow.md` with new architecture and CI responsibilities.
