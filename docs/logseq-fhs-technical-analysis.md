# Logseq FHS Packaging Technical Analysis

## Overview

Logseq is packaged from the upstream flake input and built with an Electron 37 runtime wrapped inside an FHS environment. The build graph produces two primary outputs: a deterministic `logseq-unwrapped` derivation that performs the full web/electron build, and an `logseq-fhs` wrapper that layers in runtime libraries and desktop integration. Supporting Python automation refreshes git and Yarn dependencies, injects placeholder rewrites, and maintains offline caches to preserve reproducibility.

## Module Integration (`modules/apps/logseq-fhs.nix`)

- Exposes a reusable `mkLogseqPackages` helper which imports the package set from `packages/logseq-fhs` while pinning Electron 37 and propagating the upstream source revision. The helper is reused for per-system packages and for module/app wiring.
- Provides a minimal `logseqAppModule` that injects the wrapped executable into `environment.systemPackages`. The module is exported both as `flake.nixosModules.apps.logseqFhs` (camelCase) and `flake.nixosModules.apps."logseq-fhs"` for compatibility with naming conventions, and bundled into the `workstation` profile.
- Delegates configuration to Logseq itself rather than exposing Nix options, consistent with the app-centric module approach described in the plan.

## Package Architecture (`packages/logseq-fhs/default.nix`)

### Source Patching & Git Placeholders

- Imports pre-fetched git dependencies via `git-deps.nix`, then applies `main-placeholder.patch` to replace every `:git/url` stanza in Clojure/BB workspace manifests with sentinel strings. The derivation substitutes those placeholders with store paths before builds, ensuring offline resolution and aligning with plan requirements for comprehensive placeholder coverage.
- Maintains a `placeholderSubstitutionScript` that traverses all known `.edn`/`.bb` files; missing placeholders produce a hard failure (`grep` guard) so new upstream references are detected early.

### Yarn Offline Mirrors & Resources Cache

- Enumerates every workspace lockfile through `yarn-deps.nix` and materializes offline caches with `fetchYarnDeps`. The derivation additionally constructs a custom resources workspace (via `resources-workspace.json`) to capture the Electron Forge stage, including hand-curated tarballs for `@electron/node-gyp` and the dugite native binary.
- During build, the script registers each offline cache via a helper that primes temporary writable mirrors and feeds them to `yarnConfigHook`, guaranteeing that `yarn install --offline --frozen-lockfile` succeeds across workspaces. Scoped packages in `static/yarn.lock` are rewritten using `rewrite-static-lock.py` so `resolved` entries point at the vendored cache.

### Build Phases & Tooling

- Bootstraps a deterministic Maven repository (`mavenRepo`) by running `clj -P -M:cljs` inside a fixed HOME and CA bundle, matching the plan’s guidance about cache priming.
- Forces the full upstream pipeline inside the sandbox: root install, per-workspace installs (libs, amplify, tldraw, ui), their associated build steps, and finally the Electron Forge packaging executed under `static/`. Environment variables disable telemetry and set `npm_config_nodedir` for node-gyp rebuilds. Electron artifacts and SHASUMS are injected into cache directories so Forge never downloads binaries.
- The install phase copies `static/out/Logseq-linux-x64` into `$out/share/logseq`, bundling locales and `.pak` assets, and emits a launcher that toggles Wayland behaviour when `NIXOS_OZONE_WL` is set. Desktop files and icons are propagated through `copyDesktopItems` and later stitched into the FHS wrapper.

### FHS Wrapper

- `logseq-fhs` is built via `pkgs.buildFHSEnv`. It reuses the unwrapped derivation, embeds Electron-friendly libraries (GTK stack, PipeWire/ALSA, NSS, libdrm/mesa, etc.), exports helpful defaults (`NIXOS_OZONE_WL`, `GTK_USE_PORTAL`), and symlinks a `logseq` alias for compatibility. The wrapper preserves upstream desktop metadata but switches the launcher command to `logseq-fhs %U` to ensure environment setup.

## Dependency Metadata (`packages/logseq-fhs/*.nix`)

- `git-deps.nix` enumerates every non-NPM upstream repository with pinned revisions, mirroring the automation metadata in the updater script.
- `yarn-deps.nix` stores the base32 hashes for each workspace’s offline cache, allowing incremental updates per lockfile.
- `main-placeholder.patch` transforms upstream source files to depend on placeholder tokens, covering root, per-workspace, and CLI manifests. The breadth of files indicates prior breakage scenarios (e.g., outliner/publishing) have been accounted for.
- `rewrite-static-lock.py` renames `resolved` URLs in `static/yarn.lock` to local cache filenames while preserving Yarn’s naming convention, preventing cache misses when Electron Forge resolves tarballs.

## Update Workflow (`scripts/update-logseq-sources.py`)

- Accepts an optional path to a Logseq checkout or resolves the flake input, then prefetches every git dependency with `nix-prefetch-git`, regenerating `git-deps.nix` and assembling placeholder metadata.
- Stages a temporary copy of the source tree, applies placeholder rewrites to `deps.edn`/`bb.edn`/workspace files (adding new patch hunks if upstream moved definitions), and ensures full coverage before emitting `main-placeholder.patch`.
- Rewrites all workspace lockfiles to reference local caches, copies the `node-gyp` tarball and maker repo into `.nix-cache/git/…`, and runs `prefetch-yarn-deps` for each lockfile to refresh `yarn-deps.nix` hashes. Static workspace lockfiles are rewritten via the Python helper so scoped packages map to the sanitized filenames expected by Yarn.
- Updates `resources-workspace.json` to keep the vendored `resources/package.json` and `yarn.lock` in sync, normalises references to the maker git dependency, and records the offline cache hash. Optional debug modes emit SRI forms and dump the patched tree for inspection.
- The script enforces a clean placeholder state and directs maintainers to rebuild caches after running, aligning with the plan’s emphasis on fail-fast validation.

## Alignment With Implementation Plan

- The derivation mirrors the plan’s two-stage build, explicit offline mirrors, Maven cache isolation, and Electron Forge packaging steps. Every precaution documented in the plan—placeholder substitution, resources workspace vendoring, git tarball injection, per-workspace builds—appears in the live implementation.
- Module exposure follows the prescribed `modules/apps/<tool>.nix` convention, exports both `apps.<name>` variants, and refrains from duplicate `flake.packages` entries, addressing the post-mortem lesson.
- The updater script operationalises the plan’s “prefetch helper” concept, including guardrails for new upstream workspaces and instructions to rerun formatting/linting afterward.

## Observations & Recommendations

1. **Hash Drift Visibility** – `electronArchiveHashes` currently hardcodes hashes for 37.2.6. If upstream bumps Electron, the build will fail until the hash map grows. Consider deriving hashes via `nix-prefetch-url` inside the updater or adding a failure hint to the script so maintainers know where to update.
2. **Resources Cache Regeneration** – `resources-workspace.json` holds a static lock snapshot. Documenting a workflow (or embedding into the updater) for regenerating this JSON when upstream changes the static workspace would reduce risk of stale tarball references.
3. **Runtime Dependencies** – The FHS wrapper pulls a broad set of desktop libraries but omits optional portals like `xdg-desktop-portal-gtk`. Evaluate whether additional portals or PipeWire ALSA modules improve Wayland compatibility.
4. **Testing Hooks** – Given the complex pipeline, adding automated `nix build .#logseq-unwrapped` checks to CI or `pre-commit` could catch regressions when upstream lockfiles change.
5. **Documentation Sync** – The plan mentions documenting QA steps in `nixos_docs_md/`. Ensuring future updates also refresh that location will keep operator procedures current.

Overall, the packaging faithfully implements the documented strategy, emphasizing offline repeatability, deterministic dependency pinning, and an end-user-friendly FHS wrapper.
