# nixos: Onboarding Guide

Generated from the project knowledge graph (commit `52891136`). The canonical
detail lives under `docs/architecture/`; this file is the high-level map.

## 1. Project Overview

**nixos** is a multi-host NixOS + Home Manager configuration (Infrastructure as
Code) built on the **Dendritic Pattern**: organic configuration growth where
every Nix file is a flake-parts module auto-imported via `import-tree`. Files
prefixed with `_` are omitted, and there are no literal path imports. It composes
per-host system and Home Manager configurations with sops-nix secrets, Stylix
theming, and a custom `build.sh` validate-and-deploy pipeline.

|                |                                                                                                                      |
| -------------- | -------------------------------------------------------------------------------------------------------------------- |
| **Languages**  | Nix (primary), Python, Shell, plus JSON / YAML / TOML / SQL / Markdown data                                          |
| **Frameworks** | flake-parts, import-tree, home-manager, sops-nix, stylix, treefmt-nix, git-hooks.nix, nixos-hardware, GitHub Actions |
| **Hosts**      | `system76` and `tpnix` (each opts into a shared common baseline)                                                     |

Start with `docs/architecture/README.md` for the 01-06 reading order. This guide
is the map; that doc set is the detail.

## 2. Architecture Layers

The codebase organizes into ten logical layers, from the flake root outward to
documentation.

01. **Flake Composition & Build Plumbing** (`flake.nix`, `modules/configurations`,
    `build.sh`). The entry point and the wiring that turns auto-discovered modules
    into systems: the host builder, the devshell / files / readme / package-checks
    aggregators, shared `lib` helpers, and the git post-checkout hook.

02. **Host Definitions & Baseline** (`modules/system76`, `modules/tpnix`,
    `modules/hosts/common`). Per-host configuration and hardware profiles, plus the
    cross-host shared baseline and the registry that every opted-in host composes.
    The largest layer.

03. **Base System & Boot** (`modules/base`, `modules/boot`). Foundational settings
    shared by all hosts: core Nix settings, users, locale, bootloader, and kernel.

04. **Home Manager & Dotfiles** (`modules/home-manager`, `modules/home`,
    `modules/files`). The Home Manager integration glue, per-user home
    configuration, and generated dotfile sources (bat, eza, fzf, ...).

05. **System Services & Desktop Domains** (`modules/networking`, `security`,
    `storage`, `services`, `stylix`, `git`, `xdg`, `impermanence`, `csec`, ...).
    Domain modules configuring system services and the desktop.

06. **AI Agents Configuration** (`modules/agents`). Provisions developer AI tooling
    and agent prompts (claude-code, codex), generating system prompts and tool
    settings from a single source of truth.

07. **Local Packages & Overlays** (`packages/`, `modules/custom-overlays`). Local
    derivations (with pin hashes, fixtures, and docs) and the overlay layer that
    injects each into nixpkgs. The most numerous layer.

08. **Repo Tooling, Meta & CI** (`scripts/`, `modules/meta`, `modules/packages`,
    `.github/`). Operational scripts, evaluation logic (unfree allowlist, README and
    package checks), and CI pipelines.

09. **Documentation** (`docs/`, `.agents`, root `README.md` / `CLAUDE.md` /
    `AGENTS.md`). Long-form references and agent prompt guides.

10. **Project Configuration** (`*.toml`, `.actrc`, git attributes, sops / gitleaks
    / typos / vulnix policies). Repository-level policy and tooling dotfiles.

## 3. Key Concepts

These patterns recur everywhere. Internalize them before editing.

- **Automatic module discovery (Dendritic Pattern).** `import-tree ./modules` in
  `flake.nix` auto-imports every `.nix` file as a flake-parts module. `_`-prefixed
  files are skipped (use that for experiments and private helpers). You never add a
  file to an import list; you create it in the right place.

- **Aggregator namespaces over path imports.** Modules register into and extend
  shared namespaces: `flake.nixosModules`, `flake.homeManagerModules`, `flake.lib`,
  `flake.csec`, `flake.customOverlays`. Hosts compose by namespace name (guarded
  with `lib.hasAttrByPath` for optional modules), never by literal path.

- **The Two-Context Problem.** Each file may contribute to the flake-parts outer
  scope and to inner NixOS/HM config. Know which context a given attrset targets.
  This is the single most important pitfall. See
  `docs/architecture/02-module-authoring.md`.

- **The dual-module pattern.** NixOS modules install packages; Home Manager modules
  configure them, often setting `package = null` to avoid a duplicate install.
  `modules/home-manager/base.nix` is the most-extended aggregate in the repo.

- **App catalog + override priority ladder.** `apps-base.nix` auto-imports every
  registered app (disabled by default). `apps-enable.nix` sets the default-on/off
  baseline at `lib.mkOverride 1100`. Per-host files (such as
  `modules/tpnix/apps-enable.nix`) override at `lib.mkOverride 1000` so the host
  wins; a user default (priority 100) still beats both. A flake check rejects a
  per-host override that merely duplicates the common baseline.

- **Common-vs-per-host two-stage model.** `modules/hosts/common/registry.nix`
  declares `flake.lib.nixos.hosts.<name>.shareCommon = true`.
  `modules/configurations/nixos.nix` layers the `hosts-common` aggregate before the
  per-host module so per-host overrides win.

- **Self-gating overlays.** Each entry in `modules/custom-overlays/` only joins
  `nixpkgs.overlays` when its `programs.<name>.extended.enable` flag is set, so
  unused packages never enter the closure.

- **The local package recipe.** A derivation (`packages/<name>/default.nix`) is
  pinned by a generated `hashes.json` and refreshed by an `update.py` updater.
  `restringer` is the canonical example to trace.

- **Secrets with sops-nix.** Encrypted at rest in the `secrets/` submodule. A
  dedicated age key at `/var/lib/sops-nix/key.txt` is the only decryptor
  (SSH-derived keys are force-cleared). Declare under `sops.secrets."<ns>/<name>"`,
  consume via `config.sops.secrets."<ns>/<name>".path`.

- **Single source of truth for agent config.** `modules/agents/system-prompt.nix`
  renders the shared baseline into the user-level `~/.claude/CLAUDE.md` and
  `~/.config/codex/AGENTS.md`; `modules/agents/mcp.nix` compiles per-client MCP
  server lists. Edit the source, not the rendered output.

- **Generated artifacts.** `.gitignore`, `README.md`, `.sops.yaml`, and `.actrc`
  are owned by the files module. Edit the source definitions and regenerate
  (`write-files`); drift hooks fail the build if the output is hand-edited.

- **Validate then deploy.** `build.sh` runs git hooks + `nix flake check`, then
  switches/boots via `nh os` (it refuses a dirty tree unless `--allow-dirty`).
  `.github/workflows/check.yml` enforces the same Dendritic compliance in CI.

## 4. Guided Tour

The recommended reading path, from "what is this" to "how it ships". Each step
builds on the last.

| #   | Step                                  | Read                                                                                                                                        |
| --- | ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | What this project is                  | `README.md` (the four pillars: auto-discovery, build.sh pipeline, dual package pattern, secrets)                                            |
| 2   | The Dendritic Pattern                 | `docs/architecture/README.md`, `docs/architecture/01-pattern-overview.md`                                                                   |
| 3   | The flake entry point                 | `flake.nix` (nixConfig, inputs pinned to Bad3r forks, `mkFlake { imports = [ ... (import-tree ./modules) ]; }`)                             |
| 4   | How a file becomes a module           | `docs/architecture/02-module-authoring.md` (placement rules, pkgs-vs-no-pkgs split, the Two-Context Problem)                                |
| 5   | NixOS modules & the app catalog       | `docs/architecture/03-nixos-modules.md`, `modules/hosts/common/apps-base.nix`, `apps-enable.nix`                                            |
| 6   | Assembling a host                     | `docs/architecture/05-host-composition.md`, `modules/configurations/nixos.nix`, `modules/hosts/common/registry.nix`                         |
| 7   | Per-host composition & overrides      | `modules/system76/imports.nix`, `modules/tpnix/imports.nix`, `modules/tpnix/apps-enable.nix`                                                |
| 8   | Home Manager: the dual-module pattern | `docs/architecture/04-home-manager.md`, `modules/home-manager/nixos.nix`, `base.nix`                                                        |
| 9   | Secrets with sops-nix                 | `modules/security/sops-runtime.nix`, `modules/hosts/common/sops.nix`, `modules/security/secrets.nix`                                        |
| 10  | Custom packages & overlays            | `modules/hosts/common/custom-overlays-base.nix`, `modules/custom-overlays/restringer.nix`, `packages/restringer/default.nix`, `hashes.json` |
| 11  | The AI agents layer                   | `modules/agents/system-prompt.nix`, `claude-code/home-manager.nix`, `codex/home-manager.nix`, `mcp.nix`                                     |
| 12  | Theming with Stylix                   | `modules/stylix/stylix.nix` (base16 scheme comes from the `tinted-schemes` input)                                                           |
| 13  | Validation, tooling & deployment      | `modules/devshell.nix`, `modules/meta/treefmt.nix`, `pre-commit.nix`, `build.sh`, `.github/workflows/check.yml`                             |

## 5. File Map

Key files by layer. Each layer holds many more modules; these are the
load-bearing ones.

### Flake Composition & Build Plumbing

- `flake.nix`: root entry point. Declares nixConfig, the full inputs set
  (nixpkgs/home-manager from Bad3r forks, flake-parts, import-tree, stylix,
  sops-nix, nixvim, follower pins), and builds outputs via
  `flake-parts.lib.mkFlake` importing `git-hooks.flakeModule` and
  `(import-tree ./modules)`. Seeds `_module.args` (inputs, rootPath, secretsRoot,
  pkgs, metaOwner).
- `modules/configurations/nixos.nix`: the host-construction engine. Declares
  `configurations.nixos.<name>.module` and calls `nixpkgs.lib.nixosSystem`,
  layering `hosts-common` before the per-host module.
- `build.sh`: validate-and-deploy helper. Runs hooks + flake checks, sets Nix
  build flags, switches/boots via `nh os`.

### Host Definitions & Baseline

- `modules/hosts/common/registry.nix`: opts `system76` and `tpnix` into the shared
  `hosts-common` aggregate via `shareCommon = true`.
- `modules/hosts/common/apps-base.nix`: auto-imports every app module (disabled
  until enabled).
- `modules/hosts/common/apps-enable.nix`: default-on/off baseline for hundreds of
  `programs.*`/`services.*` at `mkOverride 1100`; publishes the snapshot for the
  collision check.
- `modules/system76/imports.nix`, `modules/tpnix/imports.nix`: per-host
  composition hubs wiring base/ssh/sops/duplicati + nixos-hardware profiles.
- `modules/tpnix/apps-enable.nix`: host override demonstration (disables defaults,
  enables thinkfan at `mkOverride 1000`).

### Base System & Boot

- `modules/base/`: core Nix settings, users, locale.
- `modules/boot/`: bootloader and kernel configuration.

### Home Manager & Dotfiles

- `modules/home-manager/base.nix`: the canonical `base` HM aggregate; many
  fragments extend it.
- `modules/home-manager/nixos.nix`: wires HM into NixOS, resolves app keys from
  aggregated exports with rich error messages.
- `modules/files/`: generated dotfile sources.

### System Services & Desktop Domains

- `modules/networking/ssh.nix`: hardened openssh server + HM SSH client
  (1Password / gpg-agent identity selection, known_hosts from declared keys).
- `modules/security/sops-runtime.nix`, `modules/hosts/common/sops.nix`: sops-nix
  runtime and age-key pinning.
- `modules/git/git.nix`: Git via HM (aliases, delta, LFS, 1Password commit
  signing).
- `modules/impermanence/impermanence.nix`: btrfs `/persist` model, wipes root on
  boot.
- `modules/services/duplicati-r2.nix`: declarative Duplicati backups to Cloudflare
  R2 with runtime-materialized systemd timers.
- `modules/stylix/stylix.nix`: central theming (OneDark base16, MonoLisa,
  GTK/Qt/Firefox/mpv).
- `modules/csec/wordlists.nix`: opt-in Kali-style `/usr/share/wordlists` symlinks.

### AI Agents Configuration

- `modules/agents/system-prompt.nix`: `flake.lib.agents.systemPrompt` with ordered
  sections + render function (renders the user-level `~/.claude/CLAUDE.md` and
  `~/.config/codex/AGENTS.md`).
- `modules/agents/mcp.nix`: validates and compiles per-client MCP server lists.
- `modules/agents/claude-code/home-manager.nix`, `codex/home-manager.nix`: the
  per-client HM modules.

### Local Packages & Overlays

- `modules/hosts/common/custom-overlays-base.nix`: auto-imports every self-gating
  overlay.
- `modules/custom-overlays/restringer.nix`, `packages/restringer/default.nix`,
  `hashes.json`: the canonical local-package chain.
- `packages/<name>/update.py`: per-package pin updaters (azd, brave-origin,
  charles, electron-mail, webcrack, ...).
- `scripts/updater/` (`nix.py`, `version.py`, `bun.py`): shared updater library.

### Repo Tooling, Meta & CI

- `modules/devshell.nix` (+ `modules/devshell/pentesting.nix`): the dev shell
  (formatter toolchain, Nix LSP, lint/security tools, SOPS helpers, act wrappers).
- `modules/meta/treefmt.nix`: formatter config (nixfmt, shfmt, ruff-format, stylua,
  biome, mdformat, taplo, yamlfmt).
- `modules/meta/pre-commit.nix`: the full hook set (shellcheck, statix, gitleaks,
  drift checks, catalog sync).
- `modules/meta/hooks/apps-catalog-sync.nix`: verifies `apps-enable.nix` stays in
  sync with `modules/apps/`.
- `.github/workflows/check.yml`: CI Dendritic-compliance pipeline.

### Documentation & Project Config

- `docs/architecture/`: the canonical 01-06 reference set.
- root `README.md`, `CLAUDE.md`, `AGENTS.md`: project + agent guides (`README.md`
  is generated by the files module; the other two are maintained by hand).
- `vulnix-whitelist.toml`, `pyproject.toml`, sops/gitleaks/typos policies: repo
  policy dotfiles.

## 6. Complexity Hotspots

Approach these carefully. They concentrate the most logic or the most
cross-cutting effects.

**Architectural core (changes ripple widely)**

- `flake.nix`: the inputs set and `_module.args` seed; a mistake here breaks every
  host.
- `modules/configurations/nixos.nix`: the host builder; controls common-vs-per-host
  layering.
- `modules/hosts/common/apps-enable.nix`: the override priority ladder; baseline
  collisions fail CI.
- `modules/home-manager/nixos.nix`: app-key resolution and HM-into-NixOS wiring.

**Cross-cutting service/domain modules**

- `modules/services/duplicati-r2.nix`, `modules/lib/r2-runtime.nix`: R2 backups,
  runtime systemd materialization, external-flake gating.
- `modules/impermanence/impermanence.nix`: wipes root on boot. Edit with care.
- `modules/networking/ssh.nix`, `modules/hosts/common/usbguard.nix`:
  security-sensitive (usbguard is currently force-disabled via the module's
  `enabled` toggle; the module also disables kernel audit pending full
  LSM-stacking audit support).
- `modules/stylix/stylix.nix`: touches GTK/Qt/Firefox/mpv theming across system and
  HM.

**Agents subsystem**

- `modules/agents/mcp.nix`, `system-prompt.nix`, `skills.nix`, `codex/_*.nix`:
  single source of truth for prompts and MCP; output is generated, so fix the
  source.

**Packaging machinery (Python)**

- `packages/duplicati-r2-tools/*.py`: shared CLI substrate + extract/list commands
  and regression fixtures.
- `scripts/updater/*.py`, `packages/*/update.py`: hash-pinning updaters;
  loosely-typed JSON handled with `typing.cast`.

**CI / shell tooling**

- `.github/scripts/upstream-tracker.sh`,
  `.github/workflows/{check,update-flake}.yml`,
  `scripts/gh-cli/pr-comments-mgmt.sh`, `scripts/url-catalog-add.py`.

Note: several documents are flagged complex purely because they are long reference
material (the CloudFlare containers set, `docs/csec/*`, `docs/claude-code/*`,
`docs/architecture/02-module-authoring.md`). They are dense reading, not risky
edits.
