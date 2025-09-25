# Logseq FHS Packaging Plan

## Goals

- Build Logseq from the latest `main` commit directly within this repository (do not rely on the older nixpkgs `logseq`).
- Produce an FHS-wrapped Electron payload (`logseq-fhs`) that can run with the expected `/usr`-style filesystem without mutating the host.
- Ship desktop integration assets (icon, `.desktop` entry) while keeping writable state outside the Nix store.

## Post-Mortem Learnings

- Duplicate package wiring (`flake.packages.x86_64-linux.logseq`) caused evaluation conflicts; only surface the package through `perSystem.packages` (and `apps` if desired), letting transposition derive the `flake.packages` entry automatically. If an override is required, raise its priority explicitly via `lib.mkForce` instead of duplicate definitions.
- Network-disabled builds failed because git/yarn dependencies were not fully mirrored. Every `:git/url` and `:git/sha` must be replaced with placeholders that later resolve to prefetched store paths, and the placeholder patch has to cover **all** files where those deps appear.
- Maven cache priming originally leaked host paths by using the default HOME. For deterministic cache creation, always set `HOME=$TMPDIR/home` and point `GIT_SSL_CAINFO` at `${cacert}/etc/ssl/certs/ca-bundle.crt` while including `git` and `cacert` in the derivation inputs.
- Introducing modules without linting created avoidable churn. Before staging new modules or updating existing ones, run `nix fmt`, `statix fix`, and `statix check`, and block on any failures.
- Placeholder substitution scripts must fail loudly when upstream adds new workspaces so that our documentation stays synchronized with reality.
- We assumed `yarn electron:make` in the root project would succeed offline, but the Forge packaging actually runs from the `static/` (a.k.a. `resources/`) workspace. Without the generated lockfiles and cached tarballs for that workspace, the build stops before `static/out/` exists. We must prefetch its dependencies or vendor the lockfile that upstream emits during a connected build.
- Electron Forge pulls the git dependency `@electron/node-gyp`. Yarn’s offline mirror skips git sources, so we add a manual tarball (`node-gyp-<rev>`) to the resources cache during the build. The helper script pins the same commit so the tar step stays aligned with upstream.
- Normalising the Yarn cache after the fact turned out to be risky. We tried renaming tarballs to friendlier names such as `@scope-pkg-version.tgz`, but Yarn still expects the `_scope_pkg___pkg_version.tgz` pattern emitted by `prefetch-yarn-deps`. Rewriting `static/yarn.lock` to those friendlier names broke the install phase, and Yarn aborted even though the tarballs were present. Lesson: keep the original prefetch naming scheme and adjust `resolved` URLs (or provide additional symlinks) instead of renaming the underlying cache entries.
- Our initial rewrite logic only mirrored `@electron/node-gyp`; we assumed that changing the root workspace lockfile would be enough. In practice every workspace-specific `yarn.lock` (especially `static/yarn.lock`) must be rewritten to reference the cached tarballs, otherwise Forge reinstalls try to reach NPM. When adjusting those lockfiles, make sure the mapping logic accounts for scoped packages and translates hyphens to the underscore-heavy filenames that `prefetch-yarn-deps` produces; otherwise Yarn still reports “tarball not in cache” despite the file existing.
- We also observed `/nix/store/.../setup: line 1854: else:: command not found` after inserting additional shell/Python helpers. The message comes from malformed shell emitted by our helper loop. Treat this as a red flag that the derivation leaked broken shell and fix it before attempting another build—otherwise debugging real packaging problems becomes harder.
- Parcel-based workspaces (`packages/amplify`, `packages/tldraw`, `packages/ui`) invoke binaries declared in their own `node_modules/.bin`. When we run them without enabling `PATH`/`patchShebangs`, the commands fail. The plan now requires per-workspace installs with `--ignore-scripts`, followed by manual shebang patching and explicit build commands.
- The official pipeline is two-stage (matching `release-electron`): stage one (`gulp build`, `cljs:release-electron`, `webpack-app-build`) populates `static/` by copying the compiled assets out of `resources/`; stage two runs Electron Forge _inside `static/`_. Any offline reproduction must mirror both stages, treat `static/` as its own yarn workspace, and prefetch its dependencies separately from `resources/`.

## Upstream Touchpoints

- **install-linux.sh** shows how upstream installs release bundles (AppImage/zip), provides desktop integration, and adjusts sandbox permissions; use it as a reference for final layout.
- **build-desktop-release.yml** documents the authoritative build pipeline (gulp ➜ shadow-cljs ➜ webpack ➜ `electron:make`). We reproduce this pipeline inside Nix to stay in sync with upstream.

## Build Pipeline Design

1. **Pin sources**
   - Add/refresh a flake input (or `fetchFromGitHub`) for `logseq/logseq` pinned to the target `main` revision. Record `rev`, `date`, and the tarball hash in the derivation.
   - Maintain a helper script (`scripts/update-logseq-sources.py`) that refreshes the commit hash and regenerates all dependent hashes.

2. **Audit git dependencies**

- Enumerate every `:git/url` / `:git/sha` in `deps.edn`, `bb.edn`, and the `deps/*`, `packages/*`, and `scripts/` trees. The current `main` branch pulls at least `bb-tasks`, `rum`, `datascript`, `cljc-fsrs`, `clj-fractional-indexing`, and `cljs-http-missionary`.
- Prefetch each repository with `nix-prefetch-git`, capture `rev`/`hash`, and patch the sources so those entries become `{:local/root "@placeholder@"}`.
- Maintain `scripts/update-logseq-sources.py` so it emits a manifest mapping placeholders to git store paths and regenerates all hashes in one go.
- Make sure the placeholder patch covers **all** files that reference these deps. The current inventory (validated via `rg ':git/url' -l`) spans:
  - `deps.edn`
  - `bb.edn`
  - `deps/common/bb.edn`
  - `deps/common/deps.edn`
  - `deps/db/bb.edn`
  - `deps/db/deps.edn`
  - `deps/db/nbb.edn`
  - `deps/graph-parser/bb.edn`
  - `deps/graph-parser/deps.edn`
  - `deps/publishing/bb.edn`
  - `deps/outliner/bb.edn`
  - `deps/outliner/deps.edn`
  - `deps/cli/bb.edn`
  - `deps/shui/deps.edn`
  - `clj-e2e/deps.edn`
  - Any additional workspace introduced upstream must be appended here **before** the pipeline proceeds.

3. **Patch files**

- Maintain patch files (e.g. `main-placeholder.patch`) that replace each remote git dependency with a placeholder string.
- The derivation substitutes those placeholders with fetched store paths via `substituteInPlace`. Include every file needing modification: `deps.edn`, `bb.edn`, `deps/*/bb.edn`, `deps/*/deps.edn`, `deps/*/nbb.edn`, and any additional path identified by the detection script.
- After substitution, run a guard step (`rg '@git-'`) to verify no placeholder survived. Abort the build if any sentinel is present.

4. **Prefetch Yarn dependencies**
   - List every `yarn.lock`: root (`yarn.lock`), `scripts/yarn.lock`, `libs/yarn.lock`, each `deps/*/yarn.lock`, and each workspace in `packages/*/yarn.lock`.

- Run `prefetch-yarn-deps` for each lockfile, note the returned SHA strings, and use them in `fetchYarnDeps` so the build never reaches the network.
- Capture the Electron Forge stage as well: during stage two, the packaging workspace consumes `resources/package.json`. Run this once on a connected machine to obtain `resources/yarn.lock`, then add it (and only its dependencies) to the prefetch manifest; without it, the Forge step will re-download tarballs inside the sandbox.
- Inject a git tarball for `@electron/node-gyp` (`node-gyp-<rev>`) into the resources offline cache; this mirrors what Yarn writes into `yarn-offline-mirror` during connected builds and prevents Forge from invoking `git ls-remote` inside the sandbox.

5. **Bootstrap Maven cache**

- The derivation creates a `mavenRepo` derivation running `clj -P -M:cljs`. Set `HOME=$TMPDIR/home` so tools.deps writes its cache into a sandboxed directory. Include `git` and `cacert` in `nativeBuildInputs` and export `GIT_SSL_CAINFO=${cacert}/etc/ssl/certs/ca-bundle.crt` to avoid SSL errors when cloning.

6. **Build derivation (`logseq-unwrapped`)**
   - Patch the source tree using the placeholders above.
   - Export environment variables expected by the upstream pipeline (`LOGSEQ_SENTRY_DSN`, `ENABLE_PLUGINS`, etc.).
   - Install the root and library workspaces offline (`yarn install --offline --ignore-scripts` plus per-workspace installs for `libs`, `packages/amplify`, `packages/tldraw`, and `packages/ui`). Immediately after installing with `--ignore-scripts`, re-run the workspace-specific build commands (`yarn --cwd libs run build`, `yarn --cwd packages/amplify run build:amplify`, `yarn --cwd packages/tldraw run build`, `yarn --cwd packages/ui run build:ui`) so Parcel/Webpack regenerates the assets that Gulp expects to sync.
   - Run the desktop build trio (`yarn gulp build`, `yarn cljs:release-electron`, `yarn webpack-app-build`) to populate `static/` with the compiled Electron payload.
   - Copy the vendored `resources/yarn.lock` into `static/`, export `ELECTRON_OVERRIDE_DIST_PATH=${electron}/libexec/electron` and `ELECTRON_SKIP_BINARY_DOWNLOAD=1`, run `yarn --cwd static install --offline --ignore-optional --production=false`, patch shebangs, and invoke Electron Forge’s package step (`electron-forge package --platform linux --arch x64`) so that `static/out/Logseq-linux-x64/` is produced inside the sandbox without downloading maker binaries.
   - Install the unpacked Electron resources into `$out/share/logseq`, copy the icon, and provide the upstream `.desktop` entry.

7. **FHS wrapper (`logseq-fhs`)**
   - Use `pkgs.buildFHSEnv` with the standard Electron runtime dependencies (GTK, PipeWire/ALSA, NSS, libX11, etc.).
   - Expose a `logseq-fhs` launcher that wraps `${logseq-unwrapped}/bin/logseq`, sets Wayland/Ozone flags, and adds `--disable-setuid-sandbox` if needed.
   - Copy the `.desktop` file and icon into the FHS output and adjust `Exec=logseq-fhs %U`.

8. **Lint discipline**
   - Run `nix fmt`, `statix fix`, and `statix check` on the new module/derivation before wiring it into the flake.

## FHS Runtime Wrapper Checklist

- `targetPkgs` should include at least: `alsa-lib`, `pipewire`, `libpulseaudio`, `gtk3`, `glib`, `xdg-utils`, `xdg-desktop-portal`, `libX11`, `libXrandr`, `libdrm`, `mesa`, `libsecret`, `nss`, `dejavu-fonts`, `fontconfig`, `freetype`.
- Bind writable paths: `/run`, `/tmp`, `$XDG_RUNTIME_DIR`.
- Set helpful defaults: `ELECTRON_DISABLE_SECURITY_WARNINGS=1`, `NIXOS_OZONE_WL=1`, `GTK_USE_PORTAL=1`.

## Module Integration

- Add `modules/apps/logseq.nix` exporting:
  - `programs.logseq.enable` to install `logseq-fhs`.
  - Options for enabling Wayland tweaks, toggling plugin-related env vars, etc.
  - `xdg.desktopEntries.logseq` pointing to the FHS launcher.
- Wire `logseq-fhs` into `perSystem.packages` (optionally also `flake.apps`) and expose configuration bundles as needed. Do **not** redeclare `flake.packages` manually; rely on the automatic transposition, and use `lib.mkForce` only when a priority override is unavoidable.
- Run `nix fmt`, `statix fix`, and `statix check` over any new or modified modules before committing them.

## Verification Steps

1. Run the prefetch helper to regenerate git/Yarn hashes; ensure no `git/url` entries remain in patched sources.
2. Build `nix build .#logseq-unwrapped` to validate the from-source derivation.
3. Build `nix build .#logseq-fhs` and confirm binaries/desktop files land under `$out`.
4. Smoke-test on X11 and Wayland (login, sync, plugins, etc.).
5. Run `nix flake check` after linting; add targeted tests if necessary.

## Follow-Ups

- Investigate `electron-builder`/sandbox flags to improve security without setuid sandbox.
- Maintain `scripts/update-logseq-deps.sh` that re-prefetches git/Yarn caches whenever tracking a new commit.
- Document manual QA procedures in `nixos_docs_md/` once the module stabilizes.
