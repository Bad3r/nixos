# Logseq FHS Packaging Technical Analysis

_Date: 2025-09-26_

## Snapshot of Flake Integration

- `modules/apps/logseq-fhs.nix` wires `inputs.logseq` through `mkLogseqPackages`, exposing `logseq-fhs` and `logseq-unwrapped` via `perSystem.packages` and `flakes.nixosModules.apps` bundles. The module intentionally keeps surface area small: it only installs the wrapped desktop app into `environment.systemPackages`, relying on the FHS build for runtime quirks.
- The Electron runtime is provided by `pkgs.electron_37`; the source revision string becomes `version = "unstable-${substring 0 8 inputs.logseq.rev}"`, matching the plan’s goal of tracking upstream `main` without curating semantic releases.

## Derivation Pipeline (`packages/logseq-fhs/default.nix`)

1. **Source normalisation**
   - `git-deps.nix` resolves every upstream git dependency to an immutable fetcher. `main-placeholder.patch` rewrites Clojure workspace manifests to reference `@placeholder@` tokens, letting the build swap git URLs for local store paths later.
   - `placeholderSubstitutionScript` and `rewriteYarnLocksScript` run in `patchedSrc`, replacing placeholder markers and rewriting `yarn.lock` entries so that Yarn points to `.nix-cache/git/*` copies instead of remote git hosts.

2. **Offline Yarn caches**
   - `yarn-deps.nix` enumerates every workspace lockfile. During evaluation, `fetchYarnDeps` materialises offline mirrors for those locks. `addNodeGyp` augments the root cache with the manually bundled `node-gyp` tarball required by Electron Forge.
   - `resources-workspace.json` carries a vendored `package.json`, `yarn.lock`, and the expected `prefetch-yarn-deps` hash for the Forge packaging workspace. `resourcesOfflineCache` uses those texts to rebuild the mirror under Nix while enforcing `outputHashMode = "recursive"` for determinism.

3. **Build phase highlights**
   - `clojureWithCache` wraps the compiler toolchain so all Maven fetches stay inside `$TMPDIR/home`, aligning with the plan’s “deterministic cache creation” requirement.
   - The main build script batches workspace installs (`yarn --cwd packages/ui ...`, `yarn --cwd static ...`) with offline mirrors, patches shebangs, and executes the upstream pipeline: `gulp build`, `cljs:release-electron`, `webpack-app-build`, then Electron Forge packaging inside `static/`.
   - `rewrite-static-lock.py` post-processes `static/yarn.lock`, translating registry URLs into cache filenames that match `prefetch-yarn-deps` output. It mirrors the plan’s warning about keeping Yarn’s naming convention intact.
   - Electron assets (`electron-v37.2.6-linux-x64.zip` and `SHASUMS256.txt`) plus builder caches (AppImage, snap templates, FPM, zstd) are downloaded ahead of time and re-injected into the build via `ELECTRON_OVERRIDE_DIST_PATH`, `ELECTRON_CACHE`, and `ELECTRON_BUILDER_CACHE`.

4. **Install phase**
   - The derivation exports the unpacked app into `$out/share/logseq`, hoisting locales, `.pak` files, and the icon. A thin wrapper script resolves the correct Electron app root before launching.

## FHS Runtime Wrapper

- `buildFHSEnv` packages the unwrapped result with the full suite of Electron runtime libraries (GTK3, PipeWire/ALSA, libdrm, libX\*, NSS, libsecret, mesa). The wrapper seeds environment defaults (`ELECTRON_DISABLE_SECURITY_WARNINGS`, `GTK_USE_PORTAL`, `NIXOS_OZONE_WL`) and re-exports the desktop file so that `Exec` points at `logseq-fhs`.
- By symlinking `logseq` to the wrapper and shipping icon/desktop assets, the FHS app covers both CLI and desktop integration use-cases outlined in the plan.

## Resources Workspace Role

- `resources-workspace.json` is the single source of truth for the packaging workspace: it locks down Electron/Forge versions, injects the `electron-forge-maker-appimage` git dependency placeholder, and stores the offline hash consumed by `resourcesOfflineCache`.
- During builds, the `static` workspace copies this lockfile and `rewrite-static-lock.py` rewrites its `resolved` URLs to the local cache, ensuring Electron Forge remains offline-capable.

## Update Workflow (`scripts/update-logseq-sources.py`)

- The updater resolves the Logseq checkout (flake input or explicit path), verifies placeholder coverage, and regenerates `main-placeholder.patch` by committing placeholder substitutions in a temporary git repo.
- It rewrites every `yarn.lock` to reference local git mirrors, prefetches each workspace via `nix run nixpkgs#prefetch-yarn-deps`, and emits fresh `packages/logseq-fhs/yarn-deps.nix` entries.
- `resources` handling mirrors the runtime: the script stages the vendored `package.json`/`yarn.lock`, runs `prefetch-yarn-deps` to compute `yarn_hashes["resources"]`, and writes an updated JSON bundle.

### Regression: frozen `resources` hash

- At the final write, the script sets `resources_output_hash = resources_workspace_data.get("hash", yarn_hashes["resources"])`. When the JSON already contains a `hash`, the code reuses the old value instead of the new `prefetch` result. Any upstream change to `resources/package.json` or `resources/yarn.lock` therefore produces mismatched tarballs: the derivation expects the stale hash, while `prefetchYarnDeps` produces new content.
- Fix expectation: always store `yarn_hashes["resources"]` (falling back only if the attr is missing, e.g. migrating from legacy files). Without this, `resourcesOfflineCache` (`packages/logseq-fhs/default.nix:166-191`) will fail with an output hash mismatch on the next update.

## Alignment with `docs/logseq-fhs-plan.md`

- The implemented pipeline follows the documented stages: placeholder-driven git vending, exhaustive Yarn cache prefetching, two-phase Electron Forge packaging, and an FHSEnv wrapper with the prescribed runtime packages.
- The plan’s cautions about cache naming, offline Forge execution, and Maven home isolation are all reflected in the derivation. The outstanding gap is the updater regression above, which contradicts the “rebuild caches to validate new hashes” directive.

## Recommendations

1. Update `scripts/update-logseq-sources.py` to assign `resources_output_hash = yarn_hashes["resources"]` and optionally emit an explicit warning if the JSON value differs from the freshly computed hash.
2. Add a post-update sanity check (`nix hash convert` or even `nix build .#logseq-fhs -L`) to the contributor workflow so hash drift is caught immediately.
3. Consider capturing the computed `electronVersion` inside `resources-workspace.json` metadata to simplify cross-checks between `package.json` and the derivation when Electron releases move.
