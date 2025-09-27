# Logseq FHS Packaging Technical Analysis (Binary Release)

## Overview

Logseq is now packaged by repackaging upstream’s `Logseq-linux-x64` release archive rather than rebuilding from source. The derivation extracts the binary tree, installs it under `$out/share/logseq`, disables the built-in auto-updater hooks, and exposes the app through an FHS environment that supplies Electron’s runtime dependencies. The flake continues to publish `logseq-unwrapped` and `logseq-fhs` packages, but both are derived from the prebuilt release.

## Package Structure (`packages/logseq-fhs/default.nix`)

- **Fetch**: `fetchzip` downloads `https://github.com/logseq/logseq/releases/download/<version>/Logseq-linux-x64-<version>.zip`. The expected hash for 0.10.14 is `07b0r02qv50ckfkmq5w9r1vnhldg01hffz9hx2gl1x1dq3g39kpz`.
- **Install**: The entire `Logseq-linux-x64/` directory is copied into `$out/share/logseq`. Icons and desktop files are installed, and any `update.js` / `app-update.yml` remnants are removed to prevent auto-update failures on the read-only store.
- **Wrapper**: A `buildFHSEnv` environment wraps the unwrapped output, supplying GTK, PipeWire, NSS, and X11 libraries. The launch script (`logseq-fhs-runtime`) sets common environment variables (e.g. `NIXOS_OZONE_WL`, `GTK_USE_PORTAL`) and executes `$store_root/Logseq --disable-setuid-sandbox`.

## Module Integration (`modules/apps/logseq-fhs.nix`)

- Hard-codes the release version/hash pair and calls the package functor with `{}` to obtain Derivations.
- Publishes both `logseq-fhs-unwrapped` and `logseq-fhs` beneath `perSystem.packages`. The workstation module still installs the wrapped binary by default.

## Update Workflow

1. Bump the version/hash constants in `modules/apps/logseq-fhs.nix` and `packages/logseq-fhs/default.nix` after identifying the new upstream release.
2. Rebuild `nix build .#packages.x86_64-linux.logseq-fhs{,-unwrapped}`.
3. Launch the app to confirm runtime behaviour; verify desktop integration assets.

## Removed Tooling

- All from-source support files (`git-deps.nix`, `yarn-deps.nix`, `main-placeholder.patch`, `resources-workspace.json`, `rewrite-static-lock.py`, and `scripts/update-logseq-sources.py`) were deleted. The binary derivation has no runtime dependency on Yarn, Clojure, or Maven.

## Runtime Dependencies

- The FHS wrapper’s dependency list mirrors the previous Electron build (GTK stack, PulseAudio/PipeWire, NSS, Mesa, X11 libs). Keeping this list ensures the prebuilt Electron runtime functions identically on NixOS.

## Validation

- `nix build .#packages.x86_64-linux.logseq-fhs` (wrapped) and `.logseq-fhs-unwrapped` both succeed.
- The resulting wrapper launches the upstream binary and honours the Wayland/X11 environment variables set previously.

This shift vastly simplifies maintenance: updating Logseq now entails bumping a version/hash pair, downloading the new release, and rebuilding, rather than replaying the entire Yarn/CLJS/Electron pipeline.
