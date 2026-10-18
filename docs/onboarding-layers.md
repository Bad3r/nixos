# Onboarding: Layers and File Map

The repository's directories fall into layers, from the flake root outward to documentation.

## Layers

01. **Flake composition and build plumbing** (`flake.nix`, `modules/configurations`, `build.sh`).
    The entry point and the wiring that turns auto-discovered modules into systems: the host builder, the devshell and package-checks aggregators, shared `lib` helpers, and the git post-checkout hook.
02. **Host definitions and baseline** (`modules/hosts/<host>/`, `modules/hosts/common`).
    Per-host configuration, hardware profiles, host documentation, the cross-host shared baseline, and the registry that every opted-in host composes.
03. **Base system and boot** (`modules/base`, `modules/boot`).
    Foundational settings shared by all hosts: core Nix settings, users, locale, bootloader, and kernel.
04. **Home Manager and dotfiles** (`modules/home-manager`, `modules/home`, `modules/files`).
    The Home Manager integration glue, per-user home configuration, and generated dotfile sources.
05. **System services and desktop domains** (`modules/networking`, `security`, `services`, `stylix`, `git`, `xdg`, `csec`, ...).
    Domain modules configuring system services and the desktop.
06. **AI agents configuration** (`modules/agents`).
    Developer AI tooling and agent prompts for claude-code and codex, with system prompts and tool settings generated from a single source.
07. **Local packages and overlays** (`packages/`, `modules/hosts/common/custom-overlays-base.nix`).
    Local derivations, with pin hashes, fixtures, and docs, and the overlay layer that injects each into nixpkgs.
08. **Repo tooling, meta, and CI** (`scripts/`, `modules/meta`, `modules/packages`, `.github/`).
    Operational scripts, evaluation logic such as the unfree predicate and the README and package checks, and CI pipelines.
09. **Documentation** (`docs/`, `.agents`, and the root `README.md`, `CLAUDE.md`, and `AGENTS.md`).
    Long-form references and agent prompt guides.
10. **Project configuration** (`pyproject.toml`, git attributes, and the sops, gitleaks, and typos policies).
    Repository-level policy and tooling dotfiles.

## Flake composition

- `flake.nix`: the root entry point, which declares `nixConfig` and the inputs, builds outputs through `flake-parts.lib.mkFlake` with `(import-tree ./modules)`, and seeds `_module.args`.
- `modules/configurations/nixos.nix`: the host builder, which calls `nixpkgs.lib.nixosSystem` and layers `hosts-common` before each host module.
- `build.sh`: the validate-and-deploy helper, which runs hooks and flake checks, sets Nix build flags, and switches or boots through `nh os`.

## Hosts and baseline

- `modules/hosts/common/registry.nix`: registers each host and its `shareCommon` opt-in to the `hosts-common` aggregate.
- `modules/hosts/common/apps-base.nix`: imports every app module, each off until its row turns it on.
- `modules/hosts/common/apps-enable.nix`: the baseline app rows, and the snapshot the FR-5 check compares host rows against.
- `modules/hosts/common/imports.nix`: the fleet composition hub, wiring base, SSH, sops, Duplicati, and shared nixos-hardware profiles.
- `modules/hosts/<host>/apps-enable.nix`: a host's own rows, as in `modules/hosts/songbird/apps-enable.nix` and `modules/hosts/tpnix/apps-enable.nix`.

## Base system and boot

- `modules/base/`: core Nix settings, users, and locale.
- `modules/hosts/common/boot.nix`: the shared kernel, initrd, systemd-boot, crash dump, and sysctl policy.
- `modules/boot/`: boot compression and visual policy.

## Home Manager

- `modules/home-manager/base.nix`: the `base` Home Manager aggregate, which many fragments extend.
- `modules/home-manager/nixos.nix`: wires Home Manager into NixOS and resolves app keys from aggregated exports.
- `modules/files/`: generated dotfile sources.

## Services and desktop

- `modules/networking/ssh.nix`: the hardened OpenSSH server and the Home Manager SSH client with its identity selection and declared `known_hosts`.
- `modules/security/sops-runtime.nix` and `modules/hosts/common/sops.nix`: the sops-nix runtime and age-key pinning.
- `modules/git/git.nix`: Git through Home Manager, with aliases, delta, LFS, and commit signing.
- `modules/services/duplicati-r2.nix`: declarative Duplicati backups to Cloudflare R2 with runtime-materialized systemd timers.
- `modules/stylix/stylix.nix`: central theming for the system and Home Manager.
- `modules/csec/wordlists.nix`: opt-in Kali-style `/usr/share/wordlists` symlinks.

## AI agents

- `modules/agents/system-prompt.nix`: `flake.lib.agents.systemPrompt`, its ordered sections, and the render function for the user-level `~/.claude/CLAUDE.md` and `~/.config/codex/AGENTS.md`.
- `modules/agents/mcp.nix`: validates and compiles the per-client MCP server lists.
- `modules/agents/claude-code/home.nix` and `modules/agents/codex/home.nix`: the per-client Home Manager modules.

## Packages and overlays

- `modules/hosts/common/custom-overlays-base.nix`: derives the overlay for each app package and imports every self-gating overlay.
- `modules/apps/restringer/`, `packages/restringer/default.nix`, and `packages/restringer/hashes.json`: the local-package chain to trace.
- `packages/<name>/update.py`: the per-package pin updaters.
- `scripts/updater/`: the shared updater library.

## Tooling and CI

- `modules/meta/devshell.nix` and `modules/apps/pentesting-devshell/package.nix`: the dev shells, with the formatter toolchain, Nix LSP, lint and security tools, SOPS helpers, and act wrappers.
- `modules/meta/treefmt.nix`: the formatter configuration.
- `modules/meta/pre-commit.nix`: the git hook set.
- `modules/meta/hooks/apps-catalog-sync.nix`: keeps `modules/hosts/common/apps-enable.nix` in sync with the registered app and browser modules.
- `.github/workflows/check.yml`: the CI Dendritic-compliance pipeline.

## Documentation and project configuration

- `docs/architecture/`: the canonical architecture reference set.
- The root `README.md`, `CLAUDE.md`, and `AGENTS.md`: project and agent guides.
- `pyproject.toml` and the sops, gitleaks, and typos policies: repo policy dotfiles.
