# Logseq Git Release Flake — Final Implementation Plan (v2)

_Last updated: 2025-10-05 (UTC)_

This revision supersedes `logseq-flake-plan-final.md` by clarifying the CI build workflow and isolating it as a dedicated phase. The earlier files remain for traceability.

---

## Phase 0 · Repository Bootstrap (no changes)

1. Create `~/git/nix-logseq-git-flake` (empty Git repo) and push initial scaffold as described previously.
2. Enable GitHub Actions with write permissions.

---

## Phase 1 · Release Artifact & Manifest Specification (explicit decisions)

1. Nightly workflow runs at `cron: "0 0 * * *"` (00:00 UTC).
2. Release tag/name `nightly-${YYYYMMDD}`; asset `logseq-linux-x64-${logseqRev}.tar.gz` (x86_64 only).
3. Manifest stored at `data/logseq-nightly.json` with schema:
   ```json
   {
     "tag": "nightly-20251005",
     "publishedAt": "2025-10-05T00:18:12Z",
     "assetUrl": "https://github.com/<owner>/nix-logseq-git-flake/releases/download/nightly-20251005/logseq-linux-x64-abcdef1.tar.gz",
     "assetSha256": "sha256-…",
     "logseqRev": "abcdef1234567890",
     "logseqVersion": "nightly-20251005"
   }
   ```
4. Hosts receive new releases after they pull the latest manifest commit; systemd timer never runs `nix flake update`.
5. GitHub retains nightly releases; local machines only realise the current derivation.

---

## Phase 2 · Flake Structure & Common Assets (no change)

- Initialize flake, implement manifest loader, define runtime libs list as in prior plan.

---

## Phase 3 · CI Build Workflow (new dedicated phase)

This phase rewrites the legacy `sss-update-logseq` logic into GitHub Actions by adapting Logseq’s official `build-desktop-release.yml` for the Linux x86_64 path only.

1. **Workflow file** `.github/workflows/nightly.yml` will contain three jobs:
   - `prepare-sources` (formerly `compile-cljs` subset).
   - `build-linux-x64` (packaging job).
   - `publish-release` (manifest + release logic).
2. **prepare-sources job** (runs on `ubuntu-22.04`). Steps:
   - `actions/checkout@v4` with `ref: master`.
   - `actions/setup-node@v4` with `node-version: 22`.
   - Cache yarn (`actions/cache@v4`) using `yarn cache dir` output.
   - `actions/setup-java@v4` (`zulu`, version 11).
   - Cache Clojure deps (`~/.m2/repository`, `~/.gitlibs`).
   - `DeLaGuardo/setup-clojure@10.1` with CLI `1.11.1.1413`.
   - Run `node ./scripts/get-pkg-version.js nightly` to compute nightly version and write to `$GITHUB_OUTPUT`.
   - Update `src/main/frontend/version.cljs` to nightly version via `sed` (as in upstream).
   - Run build chain (mirrors upstream but limited to Linux path):
     ```bash
     yarn install
     gulp build
     yarn cljs:release-electron
     yarn webpack-app-build
     ```
   - Update `static/package.json` version with nightly version, save `static/VERSION`, upload `static` directory as artifact `static-bundle`.
3. **build-linux-x64 job** (needs `prepare-sources`). Steps:
   - Download `static-bundle` artifact.
   - `actions/setup-node@v4` (node 22).
   - Run `yarn install` and `yarn electron:make` inside `static` (same as upstream).
   - Collect outputs into `builds/Logseq-linux-x64-${version}.zip` (or `.tar.gz`). For our release, convert to tarball:
     ```bash
     mkdir -p builds
     tar -C static/out/Logseq-linux-x64 -czf builds/logseq-linux-x64-${version}.tar.gz .
     echo ${version} > builds/VERSION
     ```
   - Upload `builds` artifact named `linux-build`.
4. **publish-release job** (needs `build-linux-x64`). Steps:
   - Download `linux-build`.
   - Read version and compute SHA256 (`nix hash file --type sha256 --to nix-base32 builds/logseq-linux-x64-${version}.tar.gz`).
   - Create/overwrite GitHub Release `nightly-${date}` with asset using `softprops/action-gh-release@v2`.
   - Generate manifest JSON with tag, timestamp (`date -u +%Y-%m-%dT%H:%M:%SZ`), asset URL (derived from release outputs), SHA, revision (commit from repository `git rev-parse HEAD`), version string (same as tag).
   - Save manifest JSON to workspace, upload as artifact `manifest`.
   - Check out repo using `actions/checkout@v4` (with write perms), replace `data/logseq-nightly.json`, run `nix fmt`, `nix flake check`, commit `chore: bump nightly manifest`, push to `main`.
   - Run `nix build .#logseq` and `nix run .#logseq -- --version` as final gate.
5. **Reuse**: `validate.yml` reuses steps (see next phase) but also executes `nix build`/`nix run`.

---

## Phase 4 · Package Implementation (renumbered from Phase 3 before)

Implement `packages.logseq`, desktop entry, metadata, and smoke check exactly as previously defined.

---

## Phase 5 · NixOS Module (same as prior Phase 4)

Implement `services.logseq` options, systemd service running `nix build ${cfg.buildDirectory}#logseq`, timer default `02:00`.

---

## Phase 6 · Validation Workflow (`validate.yml`)

- Trigger on `push` and `pull_request`.
- Steps: checkout, install Nix, `nix flake check`, `nix build .#logseq`, `nix run .#logseq -- --version`.

---

## Phase 7 · Integration into `/home/vx/nixos`

- Add flake input, import module, remove legacy scripts, ensure package on PATH.

---

## Phase 8 · Manual Validation Checklist

- `nix flake check`, `nix build`, `nix run` locally.
- Systemd dry run & timer verification on staging host.
- Confirm nightly workflow outcome.
- Update `docs/logseq-local-workflow.md` with new architecture.

---

This version explicitly dedicates Phase 3 to rewriting the build pipeline in GitHub Actions using Logseq’s official workflow as the template, making it clear that all builds happen in CI.
