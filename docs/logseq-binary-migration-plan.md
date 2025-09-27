# Logseq Binary Packaging Migration Plan

## 1. Release Artifact Findings

- Downloaded `Logseq-linux-x64-0.10.14.zip` (sha256 `11b3837d3549e43db24a4211e5b589559f554e4a10d59f03e13a26f30e1b8db6`) and extracted to `/tmp/logseq-release/Logseq-linux-x64`.
- Layout inside the archive:
  - Top-level Electron payload (e.g. `Logseq`, `chrome-sandbox`, `chrome_crashpad_handler`, locale `.pak` assets, `libEGL.so`, `libvk_swiftshader.so`, etc.).
  - `resources/app/` tree already populated with static assets, `node_modules/`, platform-specific directories, and `package.json` (declares version `0.10.14`, devDependency `electron@34.5.6`).
  - No `static/out/…` stage—the archive is the finished Electron bundle we currently produce via `release-electron`.
  - No desktop file or system integration assets beyond icons (`resources/app/icon.png` and derivatives).

## 2. Comparison With Current From-Source Build

| Aspect | From-source derivation | Vendor release artifact |
| --- | --- | --- |
| Build inputs | Git clone of `inputs.logseq` + 12 git deps, dozens of yarn lockfiles, Maven cache | Single fixed-output zip |
| Electron version | 37.2.6 pinned in derivation | 34.5.6 embedded by upstream |
| Output layout | `$out/share/logseq/app` + locales copied from `static/out/Logseq-linux-x64` | `Logseq-linux-x64/` already matches expected layout |
| Tooling overhead | `scripts/update-logseq-sources.py`, `main-placeholder.patch`, `yarn-deps.nix`, `resources-workspace.json`, Maven bootstrap | None—hash bump updates version |
| Desktop integration | `.desktop` generated during install phase | Release lacks `.desktop` (we must continue to provide one) |
| Launcher | Wrapper execs store Electron with `--disable-setuid-sandbox` | Can call bundled `Logseq` binary with same flag |
| Offline guarantees | Painful—must regen caches for every upstream change | Hash check on single archive (still reproducible) |

## 3. Proposed Packaging Approach

1. **Introduce binary derivation**
   - Replace the `logseq-unwrapped` derivation with a simple fixed-output fetch (e.g. `fetchzip` against release URL parameterised by version & hash).
   - Install the unpacked `Logseq-linux-x64` directory under `$out/share/logseq`. Preserve permissions; ensure `chrome-sandbox` remains non-setuid.
   - Copy `resources/app/icon.png` into `$out/share/icons/hicolor/512x512/apps/logseq.png` (same as today) and place a `.desktop` template under `$out/share/applications/logseq.desktop` targeting the wrapper (`Exec=logseq-fhs %U`).

2. **Reuse FHS wrapper**
   - Keep `buildFHSEnv` wrapper but adjust the runtime script to execute `$store_root/Logseq` (bundled binary) with `--disable-setuid-sandbox` when needed. Continue exporting `NIXOS_OZONE_WL`, `GTK_USE_PORTAL`, etc.
   - Confirm runtime dependency list remains valid for Electron 34 (most likely identical); trim if desired after testing.

3. **Versioning & Flake wiring**
   - Expose release version via module (e.g. `logseqVersion = "0.10.14"`) and store hash in attrset for easy updates.
   - Remove `inputs.logseq` unless still needed elsewhere; drop module logic that infers version from flake input rev.

4. **Delete legacy build scaffolding**
   - Remove `packages/logseq-fhs/git-deps.nix`, `yarn-deps.nix`, `main-placeholder.patch`, `resources-workspace.json`, and Python helpers (`rewrite-static-lock.py`, `scripts/update-logseq-sources.py`).
   - Simplify `packages/logseq-fhs/default.nix` to only fetch, install, and wrap the binary.

## 4. Implementation Checklist

1. Add new derivation `logseq-bin` (name TBD) using `fetchzip` with version/hash attrs.
2. Update `mkLogseqPackages` (or replace entirely) to return binary variant; adjust `modules/apps/logseq-fhs.nix` to drop `inputs.logseq` dependency.
3. Move the existing wrapper script to call the bundled `Logseq` binary; verify `--disable-setuid-sandbox` and Wayland flags still apply.
4. Re-create `.desktop` entry referencing `logseq-fhs %U` (can reuse current template minus build artifacts).
5. Delete unused files & tooling (docs referencing them must be rewritten).
6. Update documentation (including `docs/logseq-fhs-plan.md`) to describe binary-based workflow, benefits, and trade-offs.
7. Run `nix fmt`, `statix`, and `nix flake check` after cleanup.
8. Execute `nix build .#logseq-fhs` to confirm the binary wrapper works offline; smoke-test on target environment.

## 5. Validation Plan

- Verify hash against upstream release before merging (document command: `nix hash to-sri --type sha256 <base32>` or `sha256sum`).
- Launch `logseq-fhs` in both X11 and Wayland sessions; confirm disable-sandbox flag prevents chromium from requiring setuid bits.
- Ensure plugin marketplace and graph loading work with bundled Electron 34—document any regressions vs current builds.
- Consider optional follow-up: create from-source package behind feature flag for contributors requiring upstream `main` builds.

## 6. Risks & Mitigations

- **Electron version lag**: we depend on upstream for security updates. Mitigation: monitor release notes; bump quickly.
- **Loss of source patching**: AGPL still allows redistribution, but applying downstream patches requires repacking. Mitigation: document a patch overlay process (e.g. unpack app, mutate, rezip) for future work.
- **Binary provenance**: rely on GitHub release integrity; note hash in docs and optionally verify GitHub release signatures if provided.

## 7. Follow-Up Documentation Tasks

- Rewrite `docs/logseq-fhs-plan.md` to reflect binary packaging flow (or mark legacy steps as historical).
- Update `docs/logseq-fhs-technical-analysis.md` to remove references to placeholder patching and the updater script.
- Record operational guidance in `nixos_docs_md/` (install steps, version bump procedure using release zip).

By adopting the upstream binary zip we eliminate the brittle offline-from-source pipeline while keeping the FHS wrapper experience unchanged for users.
