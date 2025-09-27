# Logseq FHS Packaging Plan (Binary Release)

## Goals

- Ship Logseq by repackaging the upstream Linux release archive instead of rebuilding from source.
- Keep the FHS wrapper so the application still sees a conventional `/usr` layout and required GTK/NSS runtimes on NixOS.
- Provide desktop integration (icon, `.desktop` entry) and neutralise upstream auto-updater hooks that expect mutable installs.

## Release Packaging Flow

1. **Fetch**
   - Use `fetchzip` to download `https://github.com/logseq/logseq/releases/download/<version>/Logseq-linux-x64-<version>.zip`.
   - Keep the entire `Logseq-linux-x64/` tree under `$out/share/logseq` (all binaries, locales, and `resources/app`).
   - Validate against the known `sha256` (currently `07b0r02qv50ckfkmq5w9r1vnhldg01hffz9hx2gl1x1dq3g39kpz`).

2. **Install Phase**
   - Copy the unpacked directory into `$out/share/logseq`.
   - Remove `resources/app/update.js` and `resources/app/app-update.yml` if they appear (the binary should never try to self-update).
   - Install `resources/app/icon.png` as the desktop icon and generate a `.desktop` file targeting `logseq-fhs %U`.

3. **FHS Wrapper**
   - Reuse `pkgs.buildFHSEnv` with the same runtime dependency set we previously used for Electron (GTK, PipeWire/ALSA, NSS, X11 libs, etc.).
   - The runtime script simply executes `$store_root/Logseq --disable-setuid-sandbox` and exports `NIXOS_OZONE_WL`, `GTK_USE_PORTAL`, etc.

4. **Flake Wiring**
   - `modules/apps/logseq-fhs.nix` exposes `logseq-fhs`/`logseq-fhs-unwrapped` via the flake `perSystem.packages` set, using only the hard-coded release version/hash.
   - The module no longer depends on `inputs.logseq`.

## Update Procedure

1. Determine the new upstream version and download URL.
2. Compute the `sha256` of the release archive (`nix hash to-sri --type sha256 <file>` or `nix hash path` on the unzip result); translate to base32 if needed.
3. Update `modules/apps/logseq-fhs.nix` (version/hash constants) and `packages/logseq-fhs/default.nix`.
4. Build `nix build .#packages.x86_64-linux.logseq-fhs` to ensure the wrapper still evaluates.
5. Smoke-test `logseq-fhs` under X11/Wayland and note any upstream regressions.

## Verification Checklist

- `nix build .#packages.x86_64-linux.logseq-fhs-unwrapped`
- `nix build .#packages.x86_64-linux.logseq-fhs`
- Launch `result/bin/logseq-fhs` in the target environment.
- Confirm desktop entry and icon install correctly (the FHS wrapper symlinks them into `$out`).

## Follow-ups

- Document the new release workflow in `nixos_docs_md/` (include hash command, version bump steps).
- Consider an optional source build path for contributors if needed, but keep it separate from the default binary-based packaging.
