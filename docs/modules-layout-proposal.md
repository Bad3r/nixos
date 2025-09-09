# Modules Layout: Depth-1 Restructure Proposal

## Goals

- Keep directory depth to 1 under `modules/` (i.e., `modules/<domain>/<files>.nix` only).
- Normalize names and reduce duplication so topics are discoverable and predictable.
- Preserve current flake-parts + import-tree ergonomics (no manual index files).
- Enable incremental migration with minimal risk and easy validation.

## Current Pain Points

- One nested folder (`modules/terminal/terminal-emulators/…`) violates depth-1.
- Inconsistent naming and abbreviations (e.g., `archive-mngmt`, `clipboard-mgmnt`).
- Overlapping topics (`file-management`, `file-managers`, `file-sharing`).
- Mixed patterns: some domains are single `.nix` files at `modules/`, others are folders.

## Conventions (proposed)

- Structure: one directory per domain in `modules/`; no nested folders within domains.
- Naming: kebab-case, no abbreviations; pluralize categories only when natural (`files`, `roles`).
- Files: name by capability (`swap.nix`, `vpn.nix`, `kitty.nix`). For composite domains, optional `default.nix`.
- Aggregators: keep top-level aggregators as single files (e.g., `pc.nix`, `workstation.nix`).
- Experimental: keep as `*.experimental.nix` in the same domain folder (no `.to_fix` suffixes).

### File Naming Scheme (consistent, depth-1)

- application-<program>.nix: a single app/program (GUI or CLI), possibly combining NixOS + Home Manager config.
  - Examples: `application-kitty.nix`, `application-mpv.nix`, `application-pcmanfm.nix`.
- feature-<capability>.nix: a bundle enabling a workflow or set of tools.
  - Examples: `feature-default-terminal.nix`, `feature-file-search.nix`, `feature-file-viewers.nix`.
- service-<daemon>.nix: a long‑running system service or server (NixOS focus).
  - Examples: `service-docker.nix`, `service-wireguard.nix`.
- default.nix: domain‑wide defaults or the “toolchain” for that domain.
- experimental-<name>.nix: work‑in‑progress modules replacing `.to_fix` / `.to_merge`.

Rationale: Prefixes are self‑describing, sort predictably in listings, and avoid ambiguous generic names like `view.nix`. The domain folder provides context, so names remain concise and unambiguous without nested subfolders.

## Target Layout (high level)

- Keep as domains (examples; not exhaustive): `audio`, `base`, `boot`, `cloudflare`, `containers`, `database`, `desktop`, `development`, `encryption`, `files`, `git`, `graphics`, `hardware`, `home`, `home-manager`, `impermanence`, `languages`, `media`, `messaging-apps`, `meta`, `networking`, `office`, `pc`, `roles`, `security`, `shell`, `storage`, `system-utilities`, `system76`, `terminal`, `virtualization`, `web-browsers`, `window-manager`.
- Each domain contains only `.nix` files. No subdirectories.

## Concrete Mappings (phase 1–2)

Immediate (safe) flattening:

- `modules/terminal/terminal-emulators/*.nix` → `modules/terminal/*.nix`

Consolidations and renames (to be done in a follow-up PR):

- `file-management`, `file-managers`, `file-sharing` → `files/`
  - Move all capability modules under `modules/files/` preserving descriptive filenames (e.g., `fzf.nix`, `view.nix`, `pcmanfm.nix`, `localsend.nix`, `qbittorrent.nix`).
- `archive-mngmt` → `archives` (or `archive-management` if you prefer explicitness).
- `clipboard-mgmnt` → `clipboard`.
- `media.nix`, `image-viewers`, `pdf-viewers`, `media-players` → `media/`
  - Move all modules under `modules/media/` preserving capability filenames (e.g., `feh.nix`, `evince.nix`, `zathura.nix`, `mpv.nix`, `vlc.nix`).
  - Rename any `*.nix.to_fix` or `*.nix.to_merge` to `*.experimental.nix` within `modules/media/`.
  - Convert `media.nix` to `modules/media/default.nix` when it represents an aggregate domain module.
- Ensure any `*.nix.to_fix` is renamed to `*.experimental.nix` in-place or folded into the correct domain file.

Notes:

- `import-tree` on `./modules` discovers modules by walking the tree; moving files or renaming folders does not require adding an index file. Avoid hard-coded path imports; use the existing `flake.modules.*` pattern everywhere.

## Migration Plan

1. Flatten `terminal` now (low risk): move `alacritty.nix`, `kitty.nix`, `wezterm.nix`, `cosmic-term.nix` into `modules/terminal/`; remove the now-empty folder.
2. Standardize names and merge overlapping domains in small, reviewable batches:
   - Batch A: `archive-mngmt`→`archives`, `clipboard-mgmnt`→`clipboard`.
   - Batch B: `files` consolidation.
   - Batch C: `media` consolidation and migration of `media.nix`.
3. After each batch:
   - Search/replace stray path references if any (most modules only declare `flake.modules.*`).
   - Run validation (see below).
4. Follow-up cleanup:
   - Remove obsolete folders left empty after moves.
   - Re-check duplicates and naming drift.

## Phase 3: Naming Normalization (consistent file names)

Apply the naming scheme across domains. Suggested mappings (not exhaustive):

- terminal/
  - `kitty.nix` → `application-kitty.nix`
  - `alacritty.nix` → `application-alacritty.nix`
  - `wezterm.nix` → `application-wezterm.nix`
  - `cosmic-term.nix` → `application-cosmic-term.nix`
  - `default-terminal.nix` → `feature-default-terminal.nix`
- files/
  - `view.nix` → `feature-file-viewers.nix`
  - `search.nix` → `feature-file-search.nix`
  - `tree.nix` → `application-tree.nix`
  - `fzf.nix` → `application-fzf.nix`
  - `pcmanfm.nix` → `application-pcmanfm.nix`
  - `localsend.nix` → `application-localsend.nix`
  - `qbittorrent.nix` → `application-qbittorrent.nix`
- media/
  - `feh.nix` → `application-feh.nix`
  - `evince.nix` → `application-evince.nix`
  - `zathura.nix` → `application-zathura.nix`
  - `mpv.nix` → `application-mpv.nix`
  - `vlc.nix` → `application-vlc.nix`
  - `mpv.experimental.nix` → `experimental-mpv.nix`
  - `dotool.experimental.nix` → `experimental-dotool.nix`
- archives/
  - `cli-archive-mngmt.nix` → `feature-archive-tools.nix`
  - `file-roller.nix` → `application-file-roller.nix`
- clipboard/
  - `copyq.nix` → `application-copyq.nix`

Rollout: perform renames per domain in small PRs. After each batch, run validation.

## Validation Commands

- `nix fmt`
- `nix develop -c pre-commit run --all-files`
- `generation-manager score`
- `nix flake check --accept-flake-config`

## Example: Terminal Domain (after flatten)

- `modules/terminal/default-terminal.nix` – sets default terminal (`kitty`).
- `modules/terminal/kitty.nix` – Home Manager program config.
- `modules/terminal/alacritty.nix` – Home Manager program config.
- `modules/terminal/wezterm.nix` – Home Manager program config.
- `modules/terminal/cosmic-term.nix` – NixOS package install.

This preserves current module semantics while eliminating nested directories and clarifying where to add future terminal-related modules.
